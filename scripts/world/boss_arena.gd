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
##
## M8 gate:
##   * F8: an arena may be an enclosure - `floor_rect`, its floor as a rectangle in this node's local
##     x/z (Fort Aldmere's bailey inside its curtain wall, from the layout element's `floor`). The
##     disengage rule then measures how far the giant stands outside that rectangle (outside_m), not
##     beyond inner_radius_m: the circle that fitted the plan's 120 x 90 m bailey cut through the
##     corners of the 180 x 150 m one built, and a giant standing in a corner of the closed bailey reset
##     the battle. in_bounds() counts the rectangle too.
##   * F33: the giant is told: a warning on the HUD's message line when it crosses the disengage line
##     during an engaged attempt (at most every LEAVING_WARN_EVERY_S), and a line when the attempt resets
##     (Events.hud_message; BattleBoss words them for a battle).
##   * Fix-up 1 (N4.6): the boss's own talker is the fight's ground - a giant within talking reach of an
##     NpcTalker whose npc is the boss (the Moot's challenge stone, outside the ring's gate 95.8 m from
##     its centre, beyond the 80 m line) has not left the fight (at_boss_talker).
##   * Fix-up 2 (N4.6): and so is the way there - within that reach of the straight way from the line's
##     nearest point to the talker (on_way_to_boss_talker): the stone's reach begins 2.1 m beyond the line,
##     and walking out to it warned the giant on its first tick in between.

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
## M8 gate (F33): the leaving warning is not repeated sooner than this.
const LEAVING_WARN_EVERY_S := 4.0

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
## M8 gate (F8): the arena floor as a rectangle in this node's local x/z (an enclosure); no area = the
## circle of inner_radius_m. The disengage rule and in_bounds() measure from it when it is set.
@export var floor_rect := Rect2()
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
var _leaving_warned_tick := -100000
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


## True when `point` lies inside the arena bounds: on its floor (within inner_radius_m of this node, or
## inside floor_rect when it has one) + the wall, or inside the antechamber rectangle (local x/z).
func in_bounds(point: Vector3) -> bool:
	if outside_m(point) <= WALL_MARGIN_M:
		return true
	var local := to_local(point)
	return antechamber_rect.has_area() and antechamber_rect.has_point(Vector2(local.x, local.z))


## How far `point` lies outside the arena's floor, flat (0 on it): beyond inner_radius_m of this node,
## or outside floor_rect when the arena has one (M8 gate, F8).
func outside_m(point: Vector3) -> float:
	var local := to_local(point)
	var at := Vector2(local.x, local.z)
	if floor_rect.has_area():
		var r := floor_rect.abs()
		var dx := maxf(maxf(r.position.x - at.x, 0.0), at.x - r.end.x)
		var dz := maxf(maxf(r.position.y - at.y, 0.0), at.y - r.end.y)
		return Vector2(dx, dz).length()
	return maxf(0.0, at.length() - inner_radius_m)


## M8 gate fix-up 2 (N4.6): the point of the disengage line - disengage_margin_m outside the floor (the circle
## of inner_radius_m, or floor_rect) - nearest `at` (this node's local x/z); `at` itself when it lies within
## the line.
func line_point_toward(at: Vector2) -> Vector2:
	var on_floor := at.limit_length(inner_radius_m)
	if floor_rect.has_area():
		var r := floor_rect.abs()
		on_floor = Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
	var out := at - on_floor
	if out.length() <= disengage_margin_m:
		return at
	return on_floor + out.normalized() * disengage_margin_m


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
	if b.has_method("p34_stop_return"):
		b.p34_stop_return()   # P34: a new attempt begins while the boss still walks home
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


## The disengage rule (see the class notes): ENGAGED, the giant beyond the floor + disengage_margin_m
## for disengage_s (M8 gate, F8: measured from floor_rect when the arena has one). Crossing that line
## warns the giant (F33). Fix-up 2 (N4.6): the way to the boss's own talker is the fight's ground too
## (on_way_to_boss_talker, which holds at_boss_talker's reach).
func _check_disengage(tick: int) -> void:
	if disengage_s <= 0.0:
		return
	var p := _player()
	if p == null:
		return
	if outside_m(p.global_position) <= disengage_margin_m or on_way_to_boss_talker(p):
		_outside_since = -1
		return
	if _outside_since < 0:
		_outside_since = tick
		if tick - _leaving_warned_tick >= ActionDef.seconds_to_ticks(LEAVING_WARN_EVERY_S):
			_leaving_warned_tick = tick
			Events.hud_message.emit(leaving_line(), "warn")
	elif tick - _outside_since >= ActionDef.seconds_to_ticks(disengage_s):
		disengage(tick)


## M8 gate fix-up 1 (N4.6): true while the giant is within talking reach (the talker's radius + the giant's
## capsule) of an enabled NpcTalker that speaks for this arena's boss. Harrok's challenge stone stands
## 95.8 m from the Moot's centre, beyond the 80 m disengage line, so every giant that answered the
## challenge after Harrok engaged (on entering the ring) was told "Harrok the Unbowed will recover unless
## you turn back", and lingering at the stone reset the attempt.
func at_boss_talker(p: GiantPlayer) -> bool:
	if p == null:
		return false
	var capsule := float(p.profile.get("capsule_radius_m", 0.0))
	for t in boss_talkers():
		var d := t.global_position - p.global_position
		d.y = 0.0
		if d.length() <= t.radius_m + capsule:
			return true
	return false


## M8 gate fix-up 2 (N4.6, the re-audit's walk from the Moot's engage point to the challenge stone): true while
## the giant is within talking reach (the talker's radius + the giant's capsule) of the straight way from the
## disengage line's nearest point (line_point_toward) to an enabled NpcTalker that speaks for this arena's
## boss - at_boss_talker's reach drawn back to the line. The stone's reach begins 82.1 m from the Moot's
## centre, 2.1 m beyond the 80 m line, so every way from the ring to the stone crossed a gap outside both, and
## the leaving warning came on its first tick there (at the stone the attempt no longer reset). A talker
## within the line keeps its reach alone; the ground beside the way, past the talker or round the far side of
## the ring is left as before (the Moot foot waystone, 23 m past the stone, is out of it).
func on_way_to_boss_talker(p: GiantPlayer) -> bool:
	if p == null:
		return false
	var capsule := float(p.profile.get("capsule_radius_m", 0.0))
	var local := to_local(p.global_position)
	var at := Vector2(local.x, local.z)
	for t in boss_talkers():
		var tl := to_local(t.global_position)
		var talker := Vector2(tl.x, tl.z)
		var way_point := Geometry2D.get_closest_point_to_segment(at, line_point_toward(talker), talker)
		if at.distance_to(way_point) <= t.radius_m + capsule:
			return true
	return false


## The enabled NpcTalkers in the tree that speak for this arena's boss (none without a boss_id).
func boss_talkers() -> Array[NpcTalker]:
	var out: Array[NpcTalker] = []
	if boss_id == "" or not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group("interactables"):
		var t := n as NpcTalker
		if t != null and t.enabled and t.is_inside_tree() and t.resolved_npc_id() == boss_id:
			out.append(t)
	return out


## Ends the attempt (the disengage rule; tests may call it): the arena waits with its gate open, the
## boss begins a new attempt, Events.boss_disengaged(boss, "left") and the HUD's reset line (F33). Only
## while engaged.
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
	Events.hud_message.emit(reset_line(), "bad")


## M8 gate (F33): the fight's name in the disengage lines - the boss's display name.
func fight_name() -> String:
	var e := boss_entity()
	return e.display_name() if e != null else "The boss"


## The warning when the giant crosses the disengage line during an engaged attempt (F33).
func leaving_line() -> String:
	return "%s will recover unless you turn back." % fight_name()


## The line when the attempt resets (F33).
func reset_line() -> String:
	return "%s recovered: you left the fight." % fight_name()


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
