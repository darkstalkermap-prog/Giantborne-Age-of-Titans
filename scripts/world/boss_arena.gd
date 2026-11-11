class_name BossArena
extends Node3D
## The Ogre King's arena (plan §3.12 design 4, spec 10 "Arena has a safe exit before engagement and
## a checkpoint outside"). Placed at the arena's centre (Kingsfall/BossArena in the Valley, wired
## to Kingsfall/ArenaGate, Kingsfall/Pillars and valley.area.arena_engage); group "boss_arenas".
##
##   * Before engagement the gate is open: the antechamber is a safe exit.
##   * The player entering the engage trigger begins the engagement. The gate closes behind the
##     giant - once its capsule is clear of the gateway on the arena side, never on top of it; a
##     giant that steps back out instead cancels it. At that moment every other living enemy inside
##     the arena bounds (the ring of inner_radius_m, the gateway and the antechamber) is removed -
##     EncounterDirector.despawn() for an encounter member (it returns to its encounter at home),
##     freed otherwise - then ArenaGate's collision and bars come on, the boss is told where the
##     giant is, and Events.boss_engaged is emitted.
##   * The boss's death opens the gate, sets the defeated flag (try_set_flag, first write wins)
##     and emits Events.boss_defeated (a checkpoint trigger: GameSession respawns the player at the
##     Kingsfall shrine). A level loaded with the flag set, or with the boss's kill recorded, starts
##     defeated: the gate stays open.
##   * A death in the arena reloads the last checkpoint, which reloads the level: the arena resets.
## Engagement and the gate run in Sim's POST_RESOLVE phase (HOOK_ORDER), never from a physics
## callback.
##
## P34 (plan M6-M9 §2.10, §5.13), for every boss:
##   * The disengage rule: while engaged, a giant that stays beyond inner_radius_m + DISENGAGE_MARGIN_M
##     of the centre for DISENGAGE_S ends the attempt - the arena waits again with its gate open, the
##     boss starts a new attempt (EnemyActor.p34_reset_attempt: home, full health, its first phase)
##     and Events.boss_disengaged(boss, "left") is emitted (the music returns to the zone). Entering
##     again engages a new attempt.
##   * Members of the arena's own encounter and the boss's brood (the Matriarch's whelps) are never
##     removed as intruders.
##   * A yield's decision (EnemyActor.p34_decide -> p34_on_yield_decided): Spare ends the fight as won
##     (the gate opens, the defeated flag, boss_defeated); Strike ends it when the boss dies.
##   * The boss's flight (boss_disengaged(boss, "fled"), the Matriarch's drive-out) ends it too: the
##     gate opens and the defeated flag is set, without boss_defeated.

const GROUP := "boss_arenas"
const HOOK_ORDER := 120
const DEFAULT_DEFEATED_FLAG := "world.ogre_king.defeated"
## The giant's capsule must be this far clear of the gateway (on the arena side) before the gate
## closes behind it.
const GATE_CLEARANCE_M := 0.3
## The ring's wall thickness counts as inside the bounds.
const WALL_MARGIN_M := 2.0
## P34: the disengage rule's defaults (plan M6-M9 §2.10).
const DISENGAGE_S := 5.0
const DISENGAGE_MARGIN_M := 20.0

enum State { WAITING, ENGAGING, ENGAGED, DEFEATED }
const STATE_NAMES := ["waiting", "engaging", "engaged", "defeated"]

## Entity id of the boss this arena holds.
@export var boss_id := "valley.arena.ogre_king"
## The encounter that spawns it ("" when the boss is placed in the level).
@export var encounter_id := "encounter.kingsfall_boss"
## The AreaTrigger at the arena's threshold.
@export var engage_area_id := "valley.area.arena_engage"
@export var gate_path: NodePath = ^"../ArenaGate"
@export var pillars_path: NodePath = ^"../Pillars"
## The arena floor's radius (from this node, horizontally).
@export var inner_radius_m := 40.0
## The antechamber (and gateway) in this node's local x/z: part of the arena bounds.
@export var antechamber_rect := Rect2()
## Set (first write wins) when the boss dies.
@export var defeated_flag := DEFAULT_DEFEATED_FLAG
## P34: the disengage rule (seconds beyond inner_radius_m + disengage_margin_m; 0 = never).
@export var disengage_s := DISENGAGE_S
@export var disengage_margin_m := DISENGAGE_MARGIN_M

var state: int = State.WAITING
var engaged_tick := -1
var defeated_tick := -1
## Entity ids removed from the arena at engagement (tests, debug).
var removed_intruders: Array[String] = []
## P34: attempts engaged and attempts ended by the disengage rule (tests, debug).
var attempts := 0
var disengages := 0
var _outside_since := -1
var gate: StaticBody3D
var _gate_shape: CollisionShape3D


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group("debug_info_providers")
	if not Events.area_entered.is_connected(_on_area_entered):
		Events.area_entered.connect(_on_area_entered)
	if not Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.connect(_on_entity_died)
	if not Events.boss_disengaged.is_connected(_on_boss_disengaged):
		Events.boss_disengaged.connect(_on_boss_disengaged)   # P34: a boss that fled
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_post_resolve, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)
	if Events.area_entered.is_connected(_on_area_entered):
		Events.area_entered.disconnect(_on_area_entered)
	if Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.disconnect(_on_entity_died)
	if Events.boss_disengaged.is_connected(_on_boss_disengaged):
		Events.boss_disengaged.disconnect(_on_boss_disengaged)


func _ready() -> void:
	gate = get_node_or_null(gate_path) as StaticBody3D
	_gate_shape = gate.get_node_or_null("Shape") as CollisionShape3D if gate != null else null
	_set_gate_closed(false)
	if Waystone.flag_truthy(WorldState.get_flag(defeated_flag)) or WorldState.is_killed(boss_id):
		state = State.DEFEATED


# --------------------------------------------------------------------------- queries

func state_name() -> String:
	return STATE_NAMES[state]


func is_engaged() -> bool:
	return state == State.ENGAGED


func is_defeated() -> bool:
	return state == State.DEFEATED


func is_gate_closed() -> bool:
	return gate != null and gate.visible and _gate_shape != null and not _gate_shape.disabled


## The boss's combat entity (null while it is not spawned).
func boss_entity() -> CombatEntity:
	return Sim.get_entity(boss_id)


## The boss actor (null while it is not spawned).
func boss() -> EnemyActor:
	var e := boss_entity()
	return e.actor as EnemyActor if e != null else null


## The pillars' positions (the charge ends against them).
func pillar_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var p := get_node_or_null(pillars_path)
	if p != null:
		for c in p.get_children():
			if c is Node3D:
				out.append((c as Node3D).global_position)
	return out


## True when `point` lies inside the arena bounds: within inner_radius_m (+ the wall) of this
## node, or inside the antechamber rectangle (local x/z).
func in_bounds(point: Vector3) -> bool:
	var local := to_local(point)
	if Vector2(local.x, local.z).length() <= inner_radius_m + WALL_MARGIN_M:
		return true
	return antechamber_rect.has_area() and antechamber_rect.has_point(Vector2(local.x, local.z))


func debug_lines() -> PackedStringArray:
	var b := boss_entity()
	return PackedStringArray(["ARENA %s  boss %s  gate %s" % [state_name(), "%d hp" % int(b.combatant.pools.health)
		if b != null else "absent", "closed" if is_gate_closed() else "open"]])


# --------------------------------------------------------------------------- engagement

func _on_area_entered(_tick: int, area_id: String, _entity_id: String) -> void:
	if area_id == engage_area_id and state == State.WAITING:
		state = State.ENGAGING


func _on_post_resolve(tick: int) -> void:
	if state == State.ENGAGED:
		_check_disengage(tick)   # P34: the disengage rule
		return
	if state != State.ENGAGING:
		return
	var p := _player()
	if p == null:
		return
	var side := _gateway_side(p)
	if side > 0:
		engage(tick)
	elif side < 0 and not _player_in_trigger():
		state = State.WAITING   # it stepped back out: the antechamber stays a safe exit


## Engages the boss now (the trigger's normal path ends here; tests and the bot may call it): the
## intruders go, the gate closes, the boss learns where the giant is, boss_engaged is emitted.
## Nothing happens once engaged or defeated.
func engage(tick: int = -1) -> void:
	if state == State.ENGAGED or state == State.DEFEATED:
		return
	var t := tick if tick >= 0 else Sim.tick
	_ensure_boss()
	if WorldState.is_killed(boss_id):
		_defeat(t)
		return
	_remove_intruders()
	_set_gate_closed(true)
	state = State.ENGAGED
	engaged_tick = t
	_alert_boss(t)
	attempts += 1
	_outside_since = -1
	Events.boss_engaged.emit(t, boss_id)


## +1: the giant's capsule is clear of the gateway on the arena side; -1: it is wholly outside on
## the far side; 0: in the gateway (or there is no gate: then the arena counts as entered).
func _gateway_side(p: GiantPlayer) -> int:
	if gate == null or _gate_shape == null:
		return 1
	var box := _gate_shape.shape as BoxShape3D
	var half_depth := box.size.z * 0.5 if box != null else 1.0
	var inside_sign := signf(gate.to_local(global_position).z)
	if inside_sign == 0.0:
		inside_sign = 1.0
	var z := gate.to_local(p.global_position).z * inside_sign - _gate_shape.position.z * inside_sign
	var r := EnemyActor.entity_radius(p.entity)
	if z - r > half_depth + GATE_CLEARANCE_M:
		return 1
	if z + r < -half_depth:
		return -1
	return 0


func _player_in_trigger() -> bool:
	for n in get_tree().get_nodes_in_group("area_triggers"):
		var a := n as AreaTrigger
		if a != null and a.area_id == engage_area_id:
			return a.player_inside
	return false


func _player() -> GiantPlayer:
	return get_tree().get_first_node_in_group("player") as GiantPlayer


func _director() -> EncounterDirector:
	return get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector


## The boss encounter spawns now if it has not (the budget or the radius kept it back).
func _ensure_boss() -> void:
	if boss_entity() != null or encounter_id == "":
		return
	var d := _director()
	if d == null or d.encounter_state(encounter_id) == "":
		return
	d.force_activate(encounter_id)
	d.update_now()


## Every other living enemy inside the bounds leaves: a director member is despawned (it comes
## back at home on its encounter's next activation), anything else is freed.
func _remove_intruders() -> void:
	var d := _director()
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyActor
		if e == null or not e.is_inside_tree() or e.entity == null or e.entity.combatant == null:
			continue
		if e.entity_id == boss_id or not e.entity.is_alive() or not in_bounds(e.global_position):
			continue
		if _p34_keeps(e, d):
			continue   # P34: the arena's own encounter and the boss's brood (the Matriarch's whelps) stay
		removed_intruders.append(e.entity_id)
		if d != null and d.member_status(e.entity_id) == EncounterDirector.SPAWNED:
			d.despawn(e.entity_id)
		else:
			e.ai_enabled = false
			e.queue_free()


func _alert_boss(tick: int) -> void:
	var b := boss()
	var p := _player()
	if b == null or p == null or b.brain == null:
		return
	b.brain.on_noise(tick, p.global_position, p.entity.entity_id, true)


func _set_gate_closed(closed: bool) -> void:
	if gate != null:
		gate.visible = closed
	if _gate_shape != null:
		_gate_shape.disabled = not closed


# --------------------------------------------------------------------------- the boss's death

func _on_entity_died(tick: int, id: String, _killer: String) -> void:
	if id == boss_id and state != State.DEFEATED:
		_defeat(tick)


func _defeat(tick: int) -> void:
	state = State.DEFEATED
	defeated_tick = tick
	_set_gate_closed(false)
	if defeated_flag != "":
		WorldState.try_set_flag(defeated_flag, true)
	Events.boss_defeated.emit(tick, boss_id)


# --------------------------------------------------------------------------- P34: attempts and endings

## True for an enemy that belongs to this fight: a member of the arena's own encounter, or of the
## boss's brood (its record's brood.definition).
func _p34_keeps(e: EnemyActor, d: EncounterDirector) -> bool:
	if d != null and encounter_id != "" and d.members_of(encounter_id).has(e.entity_id):
		return true
	var b := boss()
	var brood: Variant = b.record.get("brood") if b != null else null
	return typeof(brood) == TYPE_DICTIONARY and e.entity.definition_id == str((brood as Dictionary).get("definition", ""))


## The disengage rule (see the class notes): ENGAGED, the giant beyond the radius for disengage_s.
func _check_disengage(tick: int) -> void:
	if disengage_s <= 0.0:
		return
	var p := _player()
	if p == null:
		return
	var local := to_local(p.global_position)
	if Vector2(local.x, local.z).length() <= inner_radius_m + disengage_margin_m:
		_outside_since = -1
		return
	if _outside_since < 0:
		_outside_since = tick
	elif tick - _outside_since >= ActionDef.seconds_to_ticks(disengage_s):
		disengage(tick)


## Ends the attempt (the disengage rule; tests may call it): the arena waits with its gate open, the
## boss begins a new attempt, Events.boss_disengaged(boss, "left"). Only while engaged.
func disengage(tick: int = -1) -> void:
	if state != State.ENGAGED:
		return
	var t := tick if tick >= 0 else Sim.tick
	state = State.WAITING
	_outside_since = -1
	disengages += 1
	_set_gate_closed(false)
	_reset_attempt()
	Events.boss_disengaged.emit(t, boss_id, "left")


## The boss's part of a new attempt (BattleBoss resets its battle instead).
func _reset_attempt() -> void:
	var b := boss()
	if b != null and b.has_method("p34_reset_attempt"):
		b.p34_reset_attempt()


## A yielded boss's decision (EnemyActor.p34_decide, through the group): Spare wins the fight.
func p34_on_yield_decided(entity_id: String, outcome: String) -> void:
	if outcome == "spare" and entity_id == _yielding_id() and state != State.DEFEATED:
		_defeat(Sim.tick)


## The entity whose yield ends this arena's fight (the boss; BattleBoss: its commander).
func _yielding_id() -> String:
	return boss_id


func _on_boss_disengaged(tick: int, id: String, reason: String) -> void:
	if reason == "fled" and id == boss_id and state != State.DEFEATED:
		state = State.DEFEATED
		defeated_tick = tick
		_set_gate_closed(false)
		if defeated_flag != "":
			WorldState.try_set_flag(defeated_flag, true)
