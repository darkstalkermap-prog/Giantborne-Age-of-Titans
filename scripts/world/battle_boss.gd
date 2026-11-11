class_name BattleBoss
extends BossArena
## A battle as one boss (plan M6-M9 §2.10, §5.13 boss 1; P34): the Iron Regiment and Warlord Corvane
## in Fort Aldmere's inner bailey (battle id battle.iron_regiment). A BossArena (the gate behind the
## giant, the disengage rule, a checkpoint outside) whose "boss" is a set of encounters and siege
## engines it owns through the EncounterDirector, in phases:
##
##   * `phases` (export): [{"id", "below": aggregate fraction at which it begins (the first 1.0),
##     "encounters": [encounter ids it activates], "name"}] - "The Wall" at engagement, "The Charge" at
##     60 %, "The Last Stand" at 25 % (or once every unit of the phases so far has fallen, so a
##     composition never stalls). A phase begins once per attempt (phase_log): its encounters are
##     force-activated (spawning around, never inside, the giant's footprint: the director's P34 rule),
##     Events.boss_phase_changed(battle id, phase) sounds the horn and the music layer.
##   * The aggregate (aggregate(), the boss bar): the maximum health of every unit the battle's
##     encounters field for this giant - their spawn entries filtered by its stage and, on the web, by
##     each formation's kept slots (the director's own rules) - and of its engines (`engines` world ids);
##     a unit counts its current health once spawned, its full health before, nothing once dead.
##   * Corvane (`commander_id`, record yield_at with boss_id = the battle id) yields at 30 % by himself;
##     the battle makes him yield when his guard (`guard_formation`) breaks - routed, dissolved or all
##     fallen - in the last phase. The yield protocol is EnemyActor's; on it every other unit of the
##     battle stands down (EnemyActor.p34_stand_down). Spare wins the battle (boss_defeated); Strike
##     kills him (boss_defeated on his death).
##   * Engagement emits Events.boss_engaged(battle id); the disengage rule resets the battle: every
##     member leaves (EncounterDirector.p34_reset_encounter: the fallen come back, persist_death false),
##     the phases start again and boss_disengaged(battle id, "left").
##   * M8 gate (F9; plan §3.20 "every battle fits the caps on both platforms"): on engagement the
##     members of the `stand_out` encounters leave (EncounterDirector.despawn: they come back on their
##     encounter's next activation) - Fort Aldmere's gate garrison outside the portcullis, whose pikes,
##     banner and archers took the room in the formation cap and the combatants' budget the battle's
##     units need (on the web its pikes left three of the Wall's shields and their banner waiting while the
##     bar counted them) - except the crews of the battle's own engines and a unit the giant holds; and
##     the battle reserves the room of its planned units still to come in the level's caps until the
##     attempt ends (EncounterDirector.p34_reserve), so nothing that turns up later takes it either; and
##     should units of other encounters already in the world still hold that room (Ballista Ridge's
##     shield wall and crews, a column on the road), as many of them as the caps need leave too, the
##     farthest first (EncounterDirector.p34_make_room; `stood_out` lists every unit that left). Its
##     composition (the plan, the bar's aggregate) is then what actually spawns, banners first.

const BATTLE_GROUP := "battle_bosses"

## The battle's boss id (boss_engaged, boss_yielded, boss_disengaged, boss_defeated, the music).
@export var battle_id := "battle.iron_regiment"
@export var battle_name := "The Iron Regiment"
@export var phases: Array = []
## Siege engines (world ids) whose health counts in the aggregate.
@export var engines: PackedStringArray = PackedStringArray()
## Corvane's entity id and his guard's formation id (the encounter's local formation id).
@export var commander_id := ""
@export var guard_formation := ""
## M8 gate (F9): encounters whose members leave when the battle engages (see the notes).
@export var stand_out: PackedStringArray = PackedStringArray()

## The current phase (0-based; -1 before the first engagement).
var phase_index := -1
## The phases (1-based) begun in this attempt, in order.
var phase_log: Array[int] = []
## True once the battle surrendered (Corvane yielded).
var surrendered := false
## Entity ids the last engagement stood out (tests, debug).
var stood_out: Array[String] = []
var _planned: Dictionary = {}   # entity id -> max health of the planned composition (this attempt)
var _engine_max: Dictionary = {}   # world id -> max health
var _total := 0.0


func _enter_tree() -> void:
	super()
	add_to_group(BATTLE_GROUP)
	boss_id = battle_id
	encounter_id = ""
	if not Events.boss_yielded.is_connected(_on_boss_yielded):
		Events.boss_yielded.connect(_on_boss_yielded)


func _exit_tree() -> void:
	super()
	if Events.boss_yielded.is_connected(_on_boss_yielded):
		Events.boss_yielded.disconnect(_on_boss_yielded)


func _ready() -> void:
	super()
	if Waystone.flag_truthy(WorldState.get_flag(defeated_flag)) or WorldState.is_killed(commander_id):
		state = State.DEFEATED


## The commander's entity (the arena's "boss" entity: his death ends the battle).
func boss_entity() -> CombatEntity:
	return Sim.get_entity(commander_id) if commander_id != "" else null


# --------------------------------------------------------------------------- engagement and phases

func engage(tick: int = -1) -> void:
	if state == State.ENGAGED or state == State.DEFEATED:
		return
	var t := tick if tick >= 0 else Sim.tick
	_set_gate_closed(true)
	state = State.ENGAGED
	engaged_tick = t
	attempts += 1
	_outside_since = -1
	surrendered = false
	phase_index = -1
	phase_log.clear()
	_plan()
	_stand_out()
	var d := _director()
	if d != null:
		d.p34_reserve(battle_id, _planned.keys())
		stood_out.append_array(d.p34_make_room(battle_id, global_position, engines))
	_begin_phase(0, t)
	Events.boss_engaged.emit(t, battle_id)


## M8 gate (F9): the stand_out encounters' living members leave (see the notes): every one but the crews
## of the battle's engines and a unit the giant holds.
func _stand_out() -> void:
	stood_out.clear()
	var d := _director()
	if d == null:
		return
	var keep := {}
	for enc_id in stand_out:
		for entry: Variant in GameData.get_record(enc_id).get("engines", []):
			if typeof(entry) == TYPE_DICTIONARY and engines.has(str(entry.get("engine", ""))):
				for c: Variant in entry.get("crew", []):
					keep[str(c)] = true
	for enc_id in stand_out:
		for id in d.members_of(enc_id):
			if keep.has(id) or d.member_status(id) != EncounterDirector.SPAWNED:
				continue
			var n := d.spawned(id)
			if n != null and n.has_method("is_held") and bool(n.call("is_held")):
				continue
			d.despawn(id)
			stood_out.append(id)


func _on_post_resolve(tick: int) -> void:
	if state == State.ENGAGED and not surrendered:
		_battle_step(tick)
	super(tick)


## Phases by the aggregate fraction (each once per attempt); the guard's break in the last phase.
func _battle_step(tick: int) -> void:
	var frac := aggregate_fraction()
	var next := phase_index + 1
	while next < phases.size() and (frac <= float(phases[next].get("below", 0.0)) + 1e-6 or _phase_spent()):
		_begin_phase(next, tick)
		next = phase_index + 1
	if phase_index == phases.size() - 1 and guard_broken():
		var c := boss()
		if c != null and c.has_method("p34_yield"):
			c.p34_yield("guard_broken")


func _begin_phase(i: int, tick: int) -> void:
	if i <= phase_index or i >= phases.size():
		return
	phase_index = i
	phase_log.append(i + 1)
	var d := _director()
	if d != null:
		for enc: Variant in phases[i].get("encounters", []):
			d.force_activate(str(enc))
		d.update_now()
	if i > 0:
		Events.boss_phase_changed.emit(tick, battle_id, i + 1)


## True when every unit the phases begun so far fielded has fallen (or fled): the next phase begins
## then whatever the aggregate says, so a composition whose later phases weigh more than a fraction
## never stalls (the web's smaller formations).
func _phase_spent() -> bool:
	var d := _director()
	if d == null:
		return false
	var fielded := 0
	for i in range(0, phase_index + 1):
		for enc_id: Variant in phases[i].get("encounters", []):
			for id: String in d.members_of(str(enc_id)):
				if not _planned.has(id):
					continue
				var st := d.member_status(id)
				if st == EncounterDirector.UNSPAWNED or st == EncounterDirector.DESPAWNED:
					return false   # still to come
				var e := Sim.get_entity(id)
				if st == EncounterDirector.SPAWNED and e != null and e.is_alive():
					return false
				fielded += 1
	return fielded > 0


## The current phase, 1-based (0 before engagement), and how many there are (the bar's pips).
func boss_phase() -> int:
	return phase_index + 1


func phase_count() -> int:
	return phases.size()


## True when the commander's guard broke: its formation routed or dissolved, or no guard stands.
func guard_broken() -> bool:
	if guard_formation == "":
		return false
	var d := _director()
	if d == null:
		return false
	var standing := 0
	var seen := 0
	for f: Formation in d.formations():
		if f.local_id == guard_formation:
			seen += 1
			if f.dissolved or f.state in ["routed", "broken"]:
				return true
			standing += f.living_count()
	return seen > 0 and standing == 0


# --------------------------------------------------------------------------- the aggregate

## Plans this attempt's composition: every spawn of the phases' encounters this giant would meet
## (stage ranges, the web's kept formation slots) with its definition's health, and the engines.
func _plan() -> void:
	_planned.clear()
	_engine_max.clear()
	var stage := 0
	var p := _player()
	if p != null:
		stage = p.current_growth_stage()
	for ph: Dictionary in phases:
		for enc_id: Variant in ph.get("encounters", []):
			_planned.merge(planned_units(GameData.get_record(str(enc_id)), stage, LevelRoot.is_web()))
	for id in engines:
		var e := Sim.get_entity(id)
		_engine_max[id] = e.combatant.pools.health_max if e != null and e.combatant != null else 0.0
	_total = 0.0
	for v: float in _planned.values():
		_total += v
	for v: float in _engine_max.values():
		_total += v


## entity id -> maximum health of the units an encounter record fields for a giant of `stage` (0 = any)
## on the web or not: its spawn entries within their stage ranges, a formation's members only in the
## slots the web keeps (Formation.web_kept_slots with web_formation_scale) - the director's rules.
static func planned_units(enc: Dictionary, stage: int, web: bool) -> Dictionary:
	var out := {}
	var scale := clampf(float(enc.get("web_formation_scale", 1.0)), 0.0, 1.0)
	var kept := {}
	for f: Variant in enc.get("formations", []):
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var slots := []
		for s: Variant in enc.get("spawns", []):
			if typeof(s) == TYPE_DICTIONARY and str(s.get("formation", "")) == str(f.get("id", "")):
				slots.append(int(s.get("slot", 0)))
		if not EncounterDirector.stage_allows(f, stage):
			slots = []
		elif web and scale < 1.0:
			slots = Formation.web_kept_slots(slots, scale)
		kept[str(f.get("id", ""))] = slots
	for s: Variant in enc.get("spawns", []):
		if typeof(s) != TYPE_DICTIONARY or not EncounterDirector.stage_allows(s, stage):
			continue
		var form := str(s.get("formation", ""))
		if form != "" and kept.has(form) and not (kept[form] as Array).has(int(s.get("slot", 0))):
			continue
		var rec := GameData.get_record(str(s.get("definition", "")))
		out[str(s.get("entity_id", ""))] = float(rec.get("health", rec.get("max_health", 0.0)))
	return out


## {"current", "total", "fraction", "phase", "count", "name", "yielded"}: the battle's bar.
func aggregate() -> Dictionary:
	var current := 0.0
	var d := _director()
	for id: String in _planned:
		var e := Sim.get_entity(id)
		if e != null and e.combatant != null:
			current += e.combatant.pools.health if e.is_alive() else 0.0
		elif d == null or d.member_status(id) != EncounterDirector.DEAD:
			current += float(_planned[id])
	for id: String in _engine_max:
		var e := Sim.get_entity(id)
		if e != null and e.combatant != null and e.is_alive():
			current += e.combatant.pools.health
	return {"current": current, "total": _total, "fraction": current / _total if _total > 0.0 else 0.0,
		"phase": boss_phase(), "count": phase_count(), "name": battle_name, "yielded": surrendered}


func aggregate_fraction() -> float:
	return float(aggregate().fraction)


## The units planned for this attempt (entity id -> maximum health; tests, debug).
func planned() -> Dictionary:
	return _planned.duplicate()


func total_health() -> float:
	return _total


# --------------------------------------------------------------------------- endings

func _on_boss_yielded(_tick: int, id: String) -> void:
	if id != battle_id or surrendered or state != State.ENGAGED:
		return
	surrendered = true
	for uid: String in _planned:
		if uid == commander_id:
			continue
		var e := Sim.get_entity(uid)
		if e != null and e.is_alive() and is_instance_valid(e.actor) and e.actor.has_method("p34_stand_down"):
			e.actor.call("p34_stand_down")


func _on_entity_died(tick: int, id: String, _killer: String) -> void:
	if id == commander_id and commander_id != "" and state != State.DEFEATED:
		_defeat(tick)


func _yielding_id() -> String:
	return commander_id


## M8 gate (F33): the disengage lines name the battle, which regroups rather than recovers.
func fight_name() -> String:
	return battle_name


func leaving_line() -> String:
	return "%s will regroup unless you turn back." % battle_name


func reset_line() -> String:
	return "%s regrouped: you left the battle." % battle_name


## A new attempt: every member of the battle's encounters leaves (the fallen return), phases restart; the
## room its plan reserved is released (F9).
func _reset_attempt() -> void:
	var d := _director()
	if d != null:
		d.p34_release(battle_id)
		for ph: Dictionary in phases:
			for enc_id: Variant in ph.get("encounters", []):
				d.p34_reset_encounter(str(enc_id))
	phase_index = -1
	phase_log.clear()
	surrendered = false


## The battle is over (won, or its commander slain): the room its plan reserved is released (F9).
func _defeat(tick: int) -> void:
	super(tick)
	var d := _director()
	if d != null:
		d.p34_release(battle_id)


func debug_lines() -> PackedStringArray:
	var a := aggregate()
	return PackedStringArray(["BATTLE %s  %s  %d / %d  phase %d/%d%s" % [battle_id, state_name(),
		int(a.current), int(a.total), int(a.phase), int(a.count), "  (surrendered)" if surrendered else ""]])
