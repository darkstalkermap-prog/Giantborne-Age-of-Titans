class_name SiegeEngine
extends BreakableProp
## A crewed siege engine - a ballista or a catapult (P32, plan M6-M9 §2.10, §3.16, §5.11; decision
## 21). A BreakableProp (persistent world id, health, debris, saved damage) with the record's
## `engine` block, a CombatController and an AttackRunner of its own, registered with Sim as an
## actor (sim_step every tick). Group "siege_engines".
##
## Crew: an encounter's `engines` list gives it its crew (EncounterDirector, anchor P32: add_crew).
## Each crew member has a place beside the engine (crew_slot) within crew_radius_m; the engine is
## crewed while at least min_crew of them stand within that radius alive, neither fleeing, routed
## nor held. A change of crewed emits Events.siege_engine_crewed (the audio's crowd "abandon" when it
## goes false). Reload time (reload_s) runs down only while crewed (the crew hauls: ability.crew_reload).
##
## Shooting: while crewed, reloaded and free, with its target (the giant: the first living PLAYER
## entity) inside range_m [min, max] (flat) and in sight, the engine turns toward it at turn_deg_s
## and, once it faces it, takes one of the target's ranged tokens and a launch slot - the same pools
## archers and mages use (decision 25 of M2-M5: at most two ranged attackers draw at once, launches at
## one target at least LAUNCH_GAP_S apart) - and runs its action:
##   * WINDUP: the telegraph (Events.telegraph_started): the ballista's aim line from its muzzle to its
##     aim point, the catapult's circle where its stone will land. Through the whole windup the engine
##     keeps the target's launch slot (it claims it again every tick), so no other ranged attacker's
##     shot can land inside its windup and the next one comes LAUNCH_GAP_S after its launch at the
##     earliest, however long its windup is. The ballista tracks its target until the aim lock
##     (tracking_fraction of the windup, EnemyActor.aim_lock_tick) and then keeps the point: a step
##     aside after the lock dodges the bolt. The catapult commits at once: the circle lies at the
##     target's feet as the windup begins, and the stone comes down there.
##   * ACTIVE (first tick): the runner launches the projectile from the muzzle at the aim point
##     (launch_resolver); Events.siege_engine_fired; the reload starts.
##   * The ranged token goes back when the action ends (or is interrupted).
## The engine's hits strike as an 8 m attacker (the action's attacker_height_override_m, HitFactory).
##
## Stagger: the record's `poise` (a heavy blow breaks it) staggers the engine's controller: it stops
## shooting (an interrupted windup is no shot) and, staggered, it may be seized.
##
## Destruction (on_entity_died): the BreakableProp's (debris, XP, loot, saved), then the siege morale
## event - every enemy soldier on its side within morale_event_radius_m loses 20 morale (EnemyBrain's
## "siege_destroyed", debounced 2 s per unit: two engines falling within 2 s cost it once) - and its
## crew flees for good.
##
## Siege disruption (PlayerGrab, stage 6): the grab hooks EnemyActor has - grab_attach, can_be_grabbed,
## on_grabbed (out of the simulation: process mode DISABLED, its crew lost), carry, on_released
## (set down upright where the hand lets go, staggered RELEASE_RECOVERY_S) - and p32_thrown_landed for a
## thrown engine (ProjectileSystem carries it like a thrown body): it comes down where it lands and
## smashes. grab_refusal() is the engine's own rule: the giant's stage (grab_stage, the profile's
## siege_disruption) and the engine staggered or without its crew.
##
## A faction (this placement's `faction`; "" = always hostile) makes the engine follow its standing as
## a faction member does: at peace its team is NEUTRAL (it never shoots; the giant may not lock it),
## hostile it is ENEMY.
##
## M9 gate (lane aldmere): `fire_held` - a battle holds an engine's fire until the phase that brings it
## (BattleBoss: Fort Aldmere's gate-bastion ballistae join at the Charge, plan §5.13). While held it takes
## no target, so it neither turns nor shoots (in_action false); its crew stays at its place and still
## counts as its crew (crewed and the crowd's "abandon" cue are untouched), and it hauls a reload as usual.

const GROUP := "siege_engines"
## Launches at one target stay at least this far apart (with every other ranged attacker's).
const LAUNCH_GAP_S := 1.0
## The engine shoots once it faces its target within this many degrees.
const FIRE_FACING_DEG := 5.0
## The crew is counted again this often (ticks).
const CREW_CHECK_TICKS := 6
## A crew member is asked to haul (ability.crew_reload) this often while the engine reloads.
const CREW_RELOAD_EVERY_S := 2.0
## The engine turns toward a target no farther than this beyond its range (it waits otherwise).
const TURN_REACH_SLACK_M := 30.0
const CREW_RELOAD_ACTION := "ability.crew_reload"
## A newly placed engine waits this share of its reload before its first shot (a battery coming into
## action does not loose every engine at once).
const FIRST_SHOT_RELOAD_FRACTION := 0.5
## The catapult looks for its target from this high above its base (it lobs over cover).
const LOB_EYE_M := 6.0
## Where the crew stand, in the engine's own frame (it faces -Z): behind and beside it.
const CREW_SLOTS := [Vector3(-1.6, 0.0, 1.8), Vector3(1.6, 0.0, 1.8), Vector3(-2.4, 0.0, -0.2),
	Vector3(2.4, 0.0, -0.2), Vector3(0.0, 0.0, 2.6), Vector3(-2.2, 0.0, 1.0)]
## Stagger after a release (as a released body's: PlayerGrab.RELEASE_REASONS).
const RELEASE_RECOVERY_S := 0.6
## A seized engine is held this long at most (plan §3.16: 2 s), then set down.
const HOLD_TIMEOUT_S := 2.0
const SIGHT_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE
const MORALE_EVENT := &"siege_destroyed"
## The sentence PlayerGrab shows for each refusal of grab_refusal().
const REFUSAL_TEXTS := {
	"engine_stage": "Grow to stage 6 to seize siege engines.",
	"engine_crewed": "Its crew holds it: break its poise or drive the crew off first.",
}

## The faction this placement belongs to ("" = always hostile).
@export var faction := ""
## P36 (plan M6-M9 §5.10, the siege of Skarn): the props a siege line's engine bombards (world ids of
## props with a CombatEntity: Skarn's longhouses) while the giant is out of its reach - only while the
## giant stands within bombard_within_m of the prop it would strike (0 = any distance), so the siege's
## clock pauses while the giant is away; empty = the giant only (every other engine).
@export var prop_targets: PackedStringArray = PackedStringArray()
@export var bombard_within_m := 0.0
## P36: the siege line this engine belongs to ("" = none): when its group's last engine falls the line
## breaks - every soldier of its side within P36_GROUP_ROUT_M routs.
@export var siege_group := ""

## The record's engine block.
var engine: Dictionary = {}
var controller: CombatController
var runner: AttackRunner
## Facing (yaw, radians; 0 faces -Z): the whole engine turns.
var facing_yaw := 0.0
## Seconds of crewed reloading left before the next shot (0 = loaded).
var reload_left := 0.0
## Shots fired (tests, metrics).
var shots := 0
## As last announced (Events.siege_engine_crewed).
var crewed := false
## Who holds this engine (or threw it, until it lands); "" = free.
var holder_id := ""
## Whether a giant threw it (it smashes where it lands).
var thrown := false
## M9 gate: a battle holds its fire until its phase (see the notes; BattleBoss sets and clears it).
var fire_held := false

var _crew: Array = []                 ## EnemyActor (weak: freed members are pruned)
var _target_id := ""                  ## the entity the running shot is aimed at
var _aim_point := Vector3.INF         ## committed aim (catapult: from the windup's start; ballista: from the lock)
var _aim_instance := -1
var _token_key := ""
var _next_haul_tick := 0
var _grab_saved := {}
var _standing := ""


func _ready() -> void:
	super()
	add_to_group(GROUP)
	engine = record.get("engine", {})
	facing_yaw = rotation.y
	controller = CombatController.new(entity.entity_id, entity.combatant)
	controller.set_instance_source(Sim.new_instance_id)
	var shot := GameData.get_action(action_id())
	if shot != null:
		controller.add_action(shot)
	entity.controller = controller
	controller.phase_entered.connect(_on_phase_entered)
	controller.action_ended.connect(_on_action_ended)
	runner = AttackRunner.new(self, entity, controller)
	runner.launch_resolver = _resolve_launch
	reload_left = reload_s() * FIRST_SHOT_RELOAD_FRACTION
	if destroyed:
		controller.kill()
	_apply_standing()
	if faction != "" and not Events.faction_changed.is_connected(_on_faction_changed):
		Events.faction_changed.connect(_on_faction_changed)
	Sim.register_actor(entity.entity_id, self)
	p36_set_draw_range()   # P36: not drawn beyond P36_DRAW_RANGE_M


func _exit_tree() -> void:
	Sim.unregister_actor(entity.entity_id, self)
	_release_token()


# --------------------------------------------------------------------------- queries

## The engine's id in events (its world id; its CombatEntity's id too).
func engine_id() -> String:
	return world_id


## The projectile action it shoots.
func action_id() -> String:
	return str(engine.get("action", ""))


func reload_s() -> float:
	return float(engine.get("reload_s", 6.0))


func crew_radius() -> float:
	return float(engine.get("crew_radius_m", 4.0))


func min_crew() -> int:
	return int(engine.get("min_crew", 1))


## [min, max] of its range (flat, centre to centre).
func range_band() -> Vector2:
	var r: Variant = engine.get("range_m", [0.0, 100.0])
	if typeof(r) == TYPE_ARRAY and (r as Array).size() == 2:
		return Vector2(float(r[0]), float(r[1]))
	return Vector2(0.0, 100.0)


## The giant's stage that may seize this engine (siege disruption).
func grab_stage() -> int:
	return int(engine.get("grab_stage", 6))


## The action a giant hurls it with.
func throw_action_id() -> String:
	return str(engine.get("throw_action", "ability.throw_engine"))


## True for an engine whose shot is lobbed (an indirect shot: the catapult's stone, which commits at
## the windup's start and lands in its circle).
func is_indirect() -> bool:
	var a := GameData.get_action(action_id())
	return a != null and CueRouter.is_indirect(a)


## Its muzzle (the launch point), global.
func launch_point_global(_a: ActionDef = null) -> Vector3:
	var m: Variant = engine.get("muzzle_m")
	var local := Vector3(0.0, float(record.get("height_m", 3.0)) * 0.6, 0.0)
	if typeof(m) == TYPE_ARRAY and (m as Array).size() == 3:
		local = Vector3(float(m[0]), float(m[1]), float(m[2]))
	return to_global(local)


## Where the running shot flies (TelegraphVisuals' aim line; Vector3.INF when none): the committed
## point once there is one, else the target's anchor (the ballista tracking it).
func current_aim_point() -> Vector3:
	var a := controller.action if controller != null else null
	if a == null or a.hit_shape != "projectile":
		return Vector3.INF
	var phase := controller.phase()
	if phase != ActionDef.Phase.WINDUP and phase != ActionDef.Phase.ACTIVE:
		return Vector3.INF
	if _aim_instance == controller.instance_id and _aim_point != Vector3.INF:
		return _aim_point
	var t := Sim.get_entity(_target_id)
	return t.anchor_position() if t != null and t.is_alive() else Vector3.INF


## True once the running shot's aim is committed.
func aim_locked() -> bool:
	return controller != null and controller.action != null and _aim_instance == controller.instance_id \
		and _aim_point != Vector3.INF


func attack_origin_global() -> Vector3:
	return launch_point_global()


func current_weapon() -> Dictionary:
	return {}


func current_growth_stage() -> int:
	return 1


func weapon_hit_radius() -> float:
	return 0.3


func weapon_segment_global(_action: ActionDef, _f: float) -> PackedVector3Array:
	var p := launch_point_global()
	return PackedVector3Array([p, p])


## Living crew members assigned to it (any distance).
func crew() -> Array:
	_prune_crew()
	return _crew.duplicate()


## The crew members serving it now: alive, neither fleeing, routed nor held, within crew_radius_m.
func crew_count() -> int:
	var n := 0
	for c in crew():
		if serves(c):
			n += 1
	return n


## True when `actor` serves this engine now (see crew_count).
func serves(actor: Node) -> bool:
	var e := actor as EnemyActor
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or e.entity == null or not e.entity.is_alive():
		return false
	if e.is_held() or e.brain == null or e.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED,
			EnemyBrain.AIState.DEAD]:
		return false
	var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
	return d <= crew_radius() + 1e-3


## True while at least min_crew serve it.
func is_crewed() -> bool:
	return crew_count() >= maxi(1, min_crew())


## True while its controller is staggered (its poise broke).
func is_staggered() -> bool:
	return controller != null and controller.state == CombatController.State.STAGGERED


## True while it may shoot: standing, free (not held), hostile.
func can_shoot() -> bool:
	return not destroyed and entity.is_alive() and holder_id == "" and entity.team == CombatEntity.Team.ENEMY


## M9 gate: true while it is in the fight - crewed, free to shoot and its fire not held by a battle (tests, debug).
func in_action() -> bool:
	return is_crewed() and can_shoot() and not fire_held


## M9 gate: a battle holds (true) or frees (false) this engine's fire (see the notes).
func set_fire_held(held: bool) -> void:
	if fire_held == held:
		return
	fire_held = held
	if held:
		_release_token()


## The place of crew member `actor` (global; Vector3.INF when it does not serve this engine).
func crew_slot(actor: Node) -> Vector3:
	var i := _crew.find(actor)
	if i < 0:
		return Vector3.INF
	var local: Vector3 = CREW_SLOTS[i % CREW_SLOTS.size()]
	if i >= CREW_SLOTS.size():
		local *= 1.25
	return global_position + Basis(Vector3.UP, facing_yaw) * local


# --------------------------------------------------------------------------- crew

## Gives this engine a crew member (the director: an encounter's `engines`). It stands at its place.
func add_crew(actor: Node) -> void:
	if actor == null or _crew.has(actor):
		return
	_crew.append(actor)
	if actor.has_method("p32_assign_engine"):
		actor.call("p32_assign_engine", self)
	_refresh_crewed()


## A crew member leaves (despawned, or it serves elsewhere).
func remove_crew(actor: Node) -> void:
	_crew.erase(actor)
	_refresh_crewed()


func _prune_crew() -> void:
	var keep: Array = []
	for c in _crew:
		if c != null and is_instance_valid(c) and (c as Node).is_inside_tree():
			keep.append(c)
	_crew = keep


func _refresh_crewed() -> void:
	var now := is_crewed() and can_shoot()
	if now != crewed:
		crewed = now
		Events.siege_engine_crewed.emit(Sim.tick, engine_id(), crewed)


## Every crew member gives up its engine and runs (it broke, or a giant seized it).
func _crew_flee() -> void:
	for c in crew():
		if c.has_method("p32_engine_lost"):
			c.call("p32_engine_lost", self)
	_crew.clear()


# --------------------------------------------------------------------------- tick

func sim_step(tick: int, dt: float) -> void:
	controller.on_floor = true
	controller.begin_tick(tick)
	if destroyed or not entity.is_alive() or holder_id != "":
		return
	if tick % CREW_CHECK_TICKS == 0:
		_refresh_crewed()
	if crewed and reload_left > 0.0 and controller.action == null \
			and controller.state == CombatController.State.LOCOMOTION:
		reload_left = maxf(0.0, reload_left - dt)
		_haul(tick)
	var target := _target()
	_turn(target, dt)
	if controller.action != null and controller.phase() == ActionDef.Phase.WINDUP:
		_track_aim()
		_hold_launch_slot()
	elif target != null:
		_try_fire(target)
	runner.run(tick)
	entity.combatant.pools.tick(dt, true)
	entity.combatant.poise.tick(dt)


## The engine's target: the first living PLAYER entity (the giant), while it may shoot - P36: or, for a
## siege line's engine while the giant is out of its reach, the prop it bombards (p36_bombard_target).
func _target() -> CombatEntity:
	if not can_shoot() or fire_held:
		return null
	for e: CombatEntity in Sim.entities():
		if e.team == CombatEntity.Team.PLAYER and e.is_alive() and is_instance_valid(e.actor):
			if not prop_targets.is_empty() and not can_reach(e):
				var prop := p36_bombard_target(e)
				if prop != null:
					return prop
			return e
	return null


## Flat distance to `t` (centre to centre).
func flat_distance(t: CombatEntity) -> float:
	var d := (t.actor as Node3D).global_position - global_position
	return Vector2(d.x, d.z).length()


## True when `t` is inside the range band and in sight (from the muzzle; the catapult from above it).
func can_reach(t: CombatEntity) -> bool:
	if t == null or not t.is_alive():
		return false
	var band := range_band()
	var d := flat_distance(t)
	if d < band.x - 1e-3 or d > band.y + 1e-3:
		return false
	return sees(t)


func sees(t: CombatEntity) -> bool:
	var eye := global_position + Vector3.UP * LOB_EYE_M if is_indirect() else launch_point_global()
	var exclude: Array[RID] = []
	exclude.append_array(t.occlusion_rids)
	exclude.append_array(entity.occlusion_rids)
	return HitQueryAdapter.line_clear(get_world_3d().direct_space_state, eye, t.anchor_position(), SIGHT_MASK, exclude)


## The yaw that faces `point` from the engine.
func yaw_to(point: Vector3) -> float:
	var to := point - global_position
	to.y = 0.0
	return facing_yaw if to.length_squared() < 1e-4 else TargetingRules.yaw_of(to)


## Turns toward the target at turn_deg_s - while free, or (ballista) through its windup until the aim
## lock; never while a shot is committed.
func _turn(target: CombatEntity, dt: float) -> void:
	if target == null or controller.state == CombatController.State.STAGGERED:
		return
	var a := controller.action
	if a != null and (controller.phase() != ActionDef.Phase.WINDUP or aim_locked()):
		return
	if a == null and flat_distance(target) > range_band().y + TURN_REACH_SLACK_M:
		return
	var want := yaw_to((target.actor as Node3D).global_position)
	var step := deg_to_rad(float(engine.get("turn_deg_s", 30.0))) * dt
	facing_yaw = wrapf(facing_yaw + clampf(TargetingRules.yaw_delta(facing_yaw, want), -step, step), -PI, PI)
	rotation.y = facing_yaw


## Starts a shot when everything allows it: crewed, loaded, free, the target in range and sight and
## within FIRE_FACING_DEG of its facing, a ranged token and a launch slot granted.
func _try_fire(target: CombatEntity) -> void:
	if not crewed or reload_left > 0.0 or controller.state != CombatController.State.LOCOMOTION \
			or controller.action != null:
		return
	if not can_reach(target):
		return
	var want := yaw_to((target.actor as Node3D).global_position)
	if absf(rad_to_deg(TargetingRules.yaw_delta(facing_yaw, want))) > FIRE_FACING_DEG:
		return
	if not _my_turn(target.entity_id):
		return   # another engine has waited longer for a launch at this target
	var key := EnemyActor.ranged_token_key(target.entity_id)
	if not Sim.request_token(key, entity.entity_id, EnemyActor.MAX_RANGED_HOLDERS):
		return
	_token_key = key
	if not Sim.request_launch_slot(target.entity_id, entity.entity_id, ActionDef.seconds_to_ticks(LAUNCH_GAP_S)):
		_release_token()
		return
	_leave_turns(target.entity_id)
	_target_id = target.entity_id
	_aim_point = Vector3.INF
	controller.request(&"attack", {"action_id": action_id()})
	if controller.action == null or controller.action.id != action_id():
		_release_token()


## Engines ready to shoot at one target, by how long they have waited (see _my_turn): target id ->
## {engine id: [first tick it waited, last tick it asked]}.
static var _turns: Dictionary = {}


## True when no other engine still waiting for a launch at `target_id` has waited longer (ties: the
## lower id). With launches a second apart, an engine that reloads faster than its battery's turn would
## otherwise take every slot from the engines stepped after it. An entry not asked for in the last two
## ticks has left the queue.
func _my_turn(target_id: String) -> bool:
	var q: Dictionary = _turns.get(target_id, {})
	var me := engine_id()
	var mine: Array = q.get(me, [])
	if mine.is_empty() or Sim.tick - int(mine[1]) > 2 or int(mine[1]) > Sim.tick:
		mine = [Sim.tick, Sim.tick]   # a fresh wait (an old entry of this id left the queue)
	mine[1] = Sim.tick
	q[me] = mine
	_turns[target_id] = q
	for id: String in q.keys():
		var other: Array = q[id]
		if id == me:
			continue
		if Sim.tick - int(other[1]) > 2 or int(other[1]) > Sim.tick:
			q.erase(id)   # it stopped asking
			continue
		if int(other[0]) < int(mine[0]) or (int(other[0]) == int(mine[0]) and id < me):
			return false
	return true


func _leave_turns(target_id: String) -> void:
	var q: Dictionary = _turns.get(target_id, {})
	q.erase(engine_id())
	if q.is_empty():
		_turns.erase(target_id)


## Through the windup the engine claims its target's launch slot again every tick (see the notes).
func _hold_launch_slot() -> void:
	if _target_id != "":
		Sim.request_launch_slot(_target_id, entity.entity_id, 0)


## The ballista's aim lock: at aim_lock_tick of its windup it keeps the target's anchor.
func _track_aim() -> void:
	var a := controller.action
	if a == null or aim_locked() or is_indirect():
		return
	if controller.elapsed >= EnemyActor.aim_lock_tick(a):
		var t := Sim.get_entity(_target_id)
		_aim_point = t.anchor_position() if t != null and t.is_alive() else launch_point_global() \
			+ Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw)) * range_band().y
		_aim_instance = controller.instance_id
		runner.aim_point = _aim_point


## The point a lobbed stone lands on for target `t`: under its feet (the ground below its root).
func landing_point_for(t: CombatEntity) -> Vector3:
	var p := (t.actor as Node3D).global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 40.0,
		HitQueryAdapter.OCCLUDER_MASK, entity.occlusion_rids)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


func _on_phase_entered(a: ActionDef, instance_id: int, phase: int) -> void:
	if a == null or a.id != action_id():
		return
	if phase == ActionDef.Phase.WINDUP:
		_announce(a, instance_id)
	elif phase == ActionDef.Phase.ACTIVE:
		_hold_launch_slot()
		Events.siege_engine_fired.emit(Sim.tick, engine_id(), a.id, _target_id)
		shots += 1
		reload_left = reload_s()
		_next_haul_tick = Sim.tick + ActionDef.seconds_to_ticks(0.5)


## The windup's telegraph (decision 25): the ballista's aim line, the catapult's landing circle. A
## lobbed shot commits its aim here (the circle is where the stone comes down).
func _announce(a: ActionDef, instance_id: int) -> void:
	var t: Variant = a.param("telegraph")
	if typeof(t) != TYPE_DICTIONARY:
		return
	var target := Sim.get_entity(_target_id)
	var shape := str(t.get("shape", "line"))
	var radius := float(t.get("radius_m", 0.0))
	var length := 0.0
	var origin := global_position
	if is_indirect() and target != null:
		_aim_point = landing_point_for(target)
		_aim_instance = instance_id
		runner.aim_point = _aim_point
		origin = _aim_point
	match shape:
		"line":
			radius = float(t.get("width_m", 1.0)) * 0.5
			length = float(t.get("length_m", 0.0))
		"cone":
			length = radius
	Events.telegraph_started.emit(Sim.tick, entity.entity_id, a.id, _target_id, shape, origin, facing_yaw, radius,
		length, float(a.windup_ticks) / Sim.TICK_RATE)


func _on_action_ended(a: ActionDef, _instance_id: int, _interrupted: bool) -> void:
	if a != null and a.id == action_id():
		_release_token()
		_aim_point = Vector3.INF
		_aim_instance = -1


func _release_token() -> void:
	if _token_key != "" and entity != null:
		Sim.release_token(_token_key, entity.entity_id)
	_token_key = ""


## AttackRunner.launch_resolver: from the muzzle at the committed aim point (the target's anchor if
## none was kept: a test's forced shot).
func _resolve_launch(_a: ActionDef, spec: Dictionary) -> Dictionary:
	var origin := launch_point_global()
	var aim := _aim_point
	if aim == Vector3.INF:
		var t := Sim.get_entity(_target_id)
		aim = t.anchor_position() if t != null else origin + Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw)) \
			* float(spec.get("range_m", 50.0))
	return {"origin": origin, "aim": aim}


## While the engine reloads its crew hauls: one member at a time runs ability.crew_reload.
func _haul(tick: int) -> void:
	if tick < _next_haul_tick:
		return
	_next_haul_tick = tick + ActionDef.seconds_to_ticks(CREW_RELOAD_EVERY_S)
	for c in crew():
		if serves(c) and c.has_method("p32_crew_reload") and bool(c.call("p32_crew_reload")):
			return


# --------------------------------------------------------------------------- destruction

func on_entity_died(killer_id: String) -> void:
	var was := destroyed
	var side := entity.team
	# A wreck takes no side: its fall reaches its soldiers as the siege morale event only, never as an
	# ally's death (EnemyActor counts deaths of its own team; Events.entity_died follows this call).
	entity.team = CombatEntity.Team.NEUTRAL
	super(killer_id)
	if was:
		return
	_release_token()
	siege_morale_event(side)
	_crew_flee()
	_refresh_crewed()
	p36_check_group_broken(side)   # P36: a siege line's last engine breaks the line


## The siege morale event (decision 21): every soldier on this engine's side - of its team `side` when
## that is ENEMY (default: the engine's team now), or of its faction - within morale_event_radius_m gets
## "siege_destroyed" (-20, debounced 2 s per unit by its brain). Returns how many it reached.
func siege_morale_event(side: int = -1) -> int:
	if side < 0:
		side = entity.team
	var radius := float(engine.get("morale_event_radius_m", 30.0))
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyActor
		if e == null or not e.is_inside_tree() or e.entity == null or not e.entity.is_alive():
			continue
		var ours := (side == CombatEntity.Team.ENEMY and e.entity.team == CombatEntity.Team.ENEMY) \
			or (faction != "" and e.faction == faction)
		if not ours:
			continue
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d > radius + 1e-3:
			continue
		e.on_morale_event(MORALE_EVENT)
		n += 1
	return n


# --------------------------------------------------------------------------- factions

func _on_faction_changed(_tick: int, changed: String, _state: String) -> void:
	if changed == faction and is_inside_tree():
		_apply_standing()


## Team ENEMY unless its faction is at peace with the giant (NEUTRAL: it never shoots). A wreck stays
## NEUTRAL.
func _apply_standing() -> void:
	if entity == null or destroyed:
		return
	var standing := FactionState.standing(faction) if faction != "" else "hostile"
	_standing = standing
	entity.team = CombatEntity.Team.ENEMY if standing == "hostile" else CombatEntity.Team.NEUTRAL
	if entity.team != CombatEntity.Team.ENEMY:
		_release_token()
	_refresh_crewed()


# --------------------------------------------------------------------------- the giant's hand (siege disruption)

## Its attachment profile for a giant's hand (two_hand).
func grab_attach() -> String:
	return str(record.get("grab_attach", "two_hand"))


## False once broken, held or thrown, or out of the tree. The other rules are PlayerGrab's and
## grab_refusal()'s.
func can_be_grabbed() -> bool:
	return is_inside_tree() and not destroyed and entity != null and entity.is_alive() and holder_id == "" \
		and controller != null and controller.state != CombatController.State.GRABBED


func is_held() -> bool:
	return holder_id != ""


## Why a giant of growth profile `profile` may not seize this engine now ("" = it may): "engine_stage"
## below grab_stage or without the siege_disruption permission; "engine_crewed" while it is crewed and
## not staggered (plan §2.10: a staggered or uncrewed engine).
func grab_refusal(profile: Dictionary) -> String:
	var perms: Variant = profile.get("interaction_permissions", [])
	if int(profile.get("stage", 1)) < grab_stage() or typeof(perms) != TYPE_ARRAY \
			or not (perms as Array).has("siege_disruption"):
		return "engine_stage"
	if is_crewed() and not is_staggered():
		return "engine_crewed"
	return ""


func grab_anchor_local() -> Vector3:
	if _grab_saved.has("anchor"):
		return _grab_saved.anchor
	var a := get_node_or_null("Anchors/Grab") as Node3D
	if a == null:
		a = get_node_or_null("Anchors/Center") as Node3D
	return to_local(a.global_position) if a != null else Vector3.UP * float(record.get("height_m", 3.0)) * 0.5


func body_centre_local() -> Vector3:
	return Vector3.UP * float(record.get("height_m", 3.0)) * 0.5


## A giant seized it (its controller is GRABBED already): out of the simulation and physics (process
## mode DISABLED), its shot and tokens dropped, its crew runs, crewed false.
func on_grabbed(p_holder_id: String) -> void:
	if holder_id != "":
		return
	_grab_saved = {"anchor": grab_anchor_local(), "mode": process_mode, "lockable": entity.combatant.lockable}
	holder_id = p_holder_id
	entity.combatant.lockable = false
	_release_token()
	_crew_flee()
	_refresh_crewed()
	process_mode = Node.PROCESS_MODE_DISABLED


## Places the held (or flying) engine: its local point `local_point` lands on `point`.
func carry(point: Vector3, basis: Basis, local_point: Vector3) -> void:
	if holder_id != "" and process_mode != Node.PROCESS_MODE_DISABLED:
		process_mode = Node.PROCESS_MODE_DISABLED
	global_transform = Transform3D(basis, point - basis * local_point)


## The hand let go (dropped, timeout, interrupted ...): set down upright on the floor under it (else
## the first fallback with a floor), back in the simulation, staggered RELEASE_RECOVERY_S.
func on_released(reason: String, fallbacks: Array = []) -> void:
	if holder_id == "":
		return
	var inside := is_inside_tree()
	if inside:
		var yaw := global_transform.basis.get_euler().y
		var spot := floor_point(global_position, fallbacks)
		global_transform = Transform3D(Basis(Vector3.UP, yaw), spot)
		facing_yaw = wrapf(yaw, -PI, PI)
	holder_id = ""
	_restore_after_grab()
	controller.release_grabbed(reason, RELEASE_RECOVERY_S)


## A thrown engine came down at `point` (ProjectileSystem, anchor P32): set down there, then smashed by
## its thrower (one hit that breaks it, through the hit queue: its debris, the morale event, the XP).
func p32_thrown_landed(point: Vector3, thrower: Node3D, fallbacks: Array = []) -> void:
	if holder_id == "":
		return
	thrown = true
	var yaw := global_transform.basis.get_euler().y
	var spot := floor_point(point, fallbacks)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), spot)
	facing_yaw = wrapf(yaw, -PI, PI)
	holder_id = ""
	_restore_after_grab()
	controller.release_grabbed("thrown", 0.0)
	if thrower != null and is_instance_valid(thrower):
		_queue_special_hit(thrower, "throw_landing")


## Back in the simulation and physics, lockable again (after a release or a throw's landing).
func _restore_after_grab() -> void:
	process_mode = _grab_saved.get("mode", Node.PROCESS_MODE_INHERIT)
	if entity != null and entity.combatant != null:
		entity.combatant.lockable = bool(_grab_saved.get("lockable", entity.combatant.lockable))
	_grab_saved = {}


## The floor under `desired` (its root lifted off it), else under the first fallback that has one, else
## `desired` itself.
func floor_point(desired: Vector3, fallbacks: Array = []) -> Vector3:
	for c: Variant in [desired] + fallbacks:
		var p: Vector3 = c
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 60.0,
			HitQueryAdapter.OCCLUDER_MASK, [get_rid()])
		q.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return hit.position + Vector3.UP * 0.02
	return desired


# --------------------------------------------------------------------------- P36: siege lines

## P36 (plan M6-M9 §5.7, §5.10, the siege of Skarn): a siege line's engines bombard props - Skarn's
## longhouses - while the giant is out of their reach, and break as one line.
##   * p36_bombard_target(giant): the first of prop_targets still standing (a living CombatEntity in the
##     tree), inside the range band and in sight, with the giant within bombard_within_m of it (0 = any
##     distance): the siege's clock runs only while the giant is near Skarn (plan: its timer pauses
##     while the giant is more than 200 m away). Null when none qualifies (the engine aims at the giant).
##   * p36_check_group_broken(side): when the last engine of siege_group in the tree has fallen, every
##     soldier of the engine's faction (without one: every hostile) within P36_GROUP_ROUT_M routs - the
##     line breaks, so breaking the engines saves the place they bombard.
##   * p36_shot_target() (M8 gate, F12): the prop the running shot is aimed at when it is one of
##     prop_targets (a NEUTRAL longhouse). The team rule lets an ENEMY's hits reach only the PLAYER team, so
##     ProjectileSystem asks for it at launch and lets that one prop - no other neutral prop, no civilian -
##     be struck by this shot's sweep and splash (as AttackRunner's provider_target does for a raider's
##     blow): the bombardment burns what it aims at.

const P36_GROUP_ROUT_M := 160.0
## P36 (plan M6-M9 §3.8, §5.3: 40 draw calls a view): an engine's meshes (four materials) are not drawn
## beyond this - well past the longest engine range (the catapult's 180 m) and the `low` preset's
## scenery distance (220 m) - so the Aldmere March's eleven engines do not crowd the views of places
## streamed in hundreds of metres away.
const P36_DRAW_RANGE_M := 300.0


func p36_bombard_target(giant: CombatEntity) -> CombatEntity:
	if prop_targets.is_empty() or giant == null or not is_instance_valid(giant.actor):
		return null
	var gpos := (giant.actor as Node3D).global_position
	for id in prop_targets:
		var t := Sim.get_entity(id)
		if t == null or not t.is_alive() or not is_instance_valid(t.actor) or not (t.actor as Node).is_inside_tree():
			continue
		if bombard_within_m > 0.0:
			var tp := (t.actor as Node3D).global_position
			if Vector2(gpos.x - tp.x, gpos.z - tp.z).length() > bombard_within_m:
				continue
		if can_reach(t):
			return t
	return null


## M8 gate (F12): the prop of prop_targets the running shot is aimed at (a living NEUTRAL CombatEntity),
## or null - the giant, or no shot. ProjectileSystem reads it when the shot is launched (see the notes).
func p36_shot_target() -> CombatEntity:
	if prop_targets.is_empty() or _target_id == "" or not prop_targets.has(_target_id):
		return null
	var t := Sim.get_entity(_target_id)
	if t == null or not t.is_alive() or t.team != CombatEntity.Team.NEUTRAL:
		return null
	return t


## True when every engine of this engine's siege group in the tree is destroyed.
func p36_group_broken() -> bool:
	if siege_group == "" or not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group(GROUP):
		var e := n as SiegeEngine
		if e != null and e.siege_group == siege_group and not e.destroyed:
			return false
	return true


## The line breaks with its last engine: every soldier of its side within P36_GROUP_ROUT_M routs.
## Returns how many routed.
func p36_check_group_broken(side: int) -> int:
	if not p36_group_broken():
		return 0
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyActor
		if e == null or not e.is_inside_tree() or e.entity == null or not e.entity.is_alive():
			continue
		# a line with a faction routs its faction's soldiers only; a line without one, every hostile
		var ours := e.faction == faction if faction != "" \
			else (side == CombatEntity.Team.ENEMY and e.entity.team == CombatEntity.Team.ENEMY)
		if not ours:
			continue
		if Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length() > P36_GROUP_ROUT_M:
			continue
		if e.has_method("p30_force_rout"):
			e.call("p30_force_rout")
			n += 1
	if n > 0:
		Events.hud_message.emit("The siege line breaks: its soldiers flee.", "good")
	return n


## P36: the engine's meshes are not drawn beyond P36_DRAW_RANGE_M (see the constant).
func p36_set_draw_range() -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.visibility_range_end <= 0.0 or g.visibility_range_end > P36_DRAW_RANGE_M:
			g.visibility_range_end = P36_DRAW_RANGE_M
