class_name BattleBoss
extends BossArena
## A battle as one boss (plan M6-M9 §2.10, §5.13 boss 1; P34): the Iron Regiment and Warlord Corvane
## in Fort Aldmere's inner bailey (battle id battle.iron_regiment). A BossArena (the gate behind the
## giant, the disengage rule, a checkpoint outside) whose "boss" is a set of encounters and siege
## engines it owns through the EncounterDirector, in phases:
##
##   * `phases` (export): [{"id", "below": aggregate fraction at which it begins (the first 1.0) - counted
##     with the engines whole (phase_fraction, M9 gate lane ironreg below),
##     "encounters": [encounter ids it activates], "name"}] - "The Wall" at engagement, "The Charge" at
##     70 %, "The Last Stand" at 50 % (Fort Aldmere's layout; 60 % and 25 % before the M9 confirmation,
##     which the bar never reached while the battle's engines and their crews stood) (or once every unit
##     of the phases so far has fallen, so a composition never stalls). A phase begins once per attempt (phase_log): its encounters are
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
##   * M8 screenshot pass (V3): while an attempt is engaged the battle's units know where the giant is
##     (_alert_units, every tick of the battle): a living unit of its plan that is unaware hears him
##     (EnemyBrain.on_noise, certain), as an arena's boss is told at engagement (BossArena._alert_boss).
##     The director shares awareness only within one encounter, and Fort Aldmere's Charge spawned its six
##     riders at the stables 85-110 m from where the giant fights the Wall - beyond their 70 m sight and
##     30 m hearing - where they stood for the rest of the battle. Units walking home, held by the giant,
##     fleeing, routed or dead are left out.
##   * M8 release (R1, the release check's blocker): a battle that engages after a load is always a full,
##     winnable attempt. A checkpoint taken mid-battle (one deferred from before it, committed as the Wall
##     fell) saved the Wall's encounter cleared with the battle not won; its units come back for every
##     attempt (persist_death false), so after a death reload or a quit and Continue the battle engaged again
##     and waited on a Wall the director would never spawn - the portcullis down behind the giant. Now:
##       - no checkpoint is committed while the battle is engaged (GameSession's fight blocker, P06.md);
##       - every engagement starts its phases' encounters afresh (_fresh_encounters:
##         EncounterDirector.p34_reset_encounter, as the disengage rule does), whatever a load left;
##       - a battle not over repairs a save written mid-battle as it loads (_repair_after_load: its phases'
##         cleared flags lifted, `repaired` lists them), so the save holds no fallen phase any more;
##       - a phase never waits on units that will never come: units of a cleared encounter that are not up
##         count as fallen (and nothing in the bar), and a unit of a begun phase that left the world without
##         falling (despawned) is called back (_recall_despawned: its encounter activated again);
##       - the room the battle reserved is released if its node leaves the tree engaged.
##   * M9 gate (lane aldmere; plan §5.13: "The Wall ... two wall ballistae fire", "The Charge ... all four
##     ballistae fire"): an engine of the battle that a later phase's encounter names in its `engines` list
##     (with its own crew, or none: a crew of another encounter serves it) holds its fire until that phase
##     begins (SiegeEngine.set_fire_held; engine_phase, held_engines): Fort Aldmere's Charge names the gate
##     bastions' two ballistae, which the gate garrison's wall crews serve, so the Wall faces the two inner
##     ballistae its own encounter crews and the Charge and the Last Stand all four. Before, all four shot
##     from the Wall's first blow - the bastion pair 16 m up behind a giant at the bailey's gate end, which
##     a stage-4 giant can neither reach nor see from there - and killed the novice at stage 4 before the
##     Charge (docs/BALANCE_LOG.md, "M9 gate (lane aldmere)"). A reset, a win or the node leaving the tree
##     frees every hold. The giant is told which engines shoot (engines_line, a HUD line as the battle
##     engages: "Smash the ballistae: two shoot now, two more at the Charge."; and
##     phase_engines_line as a phase frees held ones: "Two more ballistae open fire."): the engines take
##     most of the giant's health in the battle, and the quest's word for them was only in the journal.
##   * M9 gate (lane ironreg; the review's major finding): the phases follow the units, not the engines
##     (phase_fraction: the aggregate with every engine counted at its full health). The thresholds were set
##     with the four ballistae standing - 3,600 of the bar, 25.6 % on the desktop and 30.7 % on the web - and a
##     wrecked engine kept its maximum in the total (a wreck persists; the reset does not mend it), so a giant
##     who smashed the gate bastions' pair on the way in started the battle at 0.872 and met the Charge's six
##     riders and the Last Stand together as the Wall fell (0.494); on the web, all four smashed, the Charge came
##     with the Wall (0.693 as it engaged); a ballista smashed mid-Wall brought the Charge on before the Wall
##     fell. The bar the giant sees (aggregate) still counts what the engines have left.

const BATTLE_GROUP := "battle_bosses"
## M9 gate: the engines' holds are applied again this often while engaged (an engine streamed in since).
const ENGINE_HOLD_CHECK_TICKS := 30

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
## M8 release (R1): the encounters whose cleared flag the battle lifted as it loaded (tests, debug).
var repaired: Array[String] = []
## M9 gate: the battle's engines whose fire this attempt holds until their phase (world id -> phase index).
var held_engines: Dictionary = {}
var _planned: Dictionary = {}   # entity id -> max health of the planned composition (this attempt)
var _unit_encounter: Dictionary = {}   # planned entity id -> its encounter id
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
	if state == State.ENGAGED:
		var d := _director()   # M8 release (R1): an attempt left engaged keeps no room in the caps
		if d != null:
			d.p34_release(battle_id)
	_free_engine_holds()   # M9 gate


func _ready() -> void:
	super()
	if Waystone.flag_truthy(WorldState.get_flag(defeated_flag)) or WorldState.is_killed(commander_id):
		state = State.DEFEATED
	_repair_after_load()


## True once the battle is over for good (won; FortBattle: or settled) - a load keeps its phases as they are.
func battle_over() -> bool:
	return state == State.DEFEATED


## The encounter ids of every phase, in phase order.
func phase_encounters() -> PackedStringArray:
	var out := PackedStringArray()
	for ph: Dictionary in phases:
		for enc_id: Variant in ph.get("encounters", []):
			if not out.has(str(enc_id)):
				out.append(str(enc_id))
	return out


## M8 release (R1): a battle not over has no fallen phase. A save written mid-battle by an older build (the
## Wall's encounter cleared, the battle not won) loads with that encounter cleared, which the director never
## activates again; as the battle loads, each cleared encounter of its phases is set back - its flag lifted
## (the director reads it after this when both load with the level) and the director's encounter reset when
## it has read it already (a chunk streamed in later) - as the disengage rule resets them. A battle won keeps
## its phases.
func _repair_after_load() -> void:
	repaired.clear()
	if battle_over():
		return
	var d := _director()
	for enc_id in phase_encounters():
		var flag := EncounterDirector.cleared_flag(enc_id)
		var stale := Waystone.flag_truthy(WorldState.get_flag(flag))
		if d != null and d.encounter_state(enc_id) == EncounterDirector.CLEARED:
			d.p34_reset_encounter(enc_id)
			stale = true
		if stale:
			WorldState.set_flag(flag, false)
			repaired.append(enc_id)


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
	_fresh_encounters()
	_plan()
	_stand_out()
	var d := _director()
	if d != null:
		d.p34_reserve(battle_id, _planned.keys())
		stood_out.append_array(d.p34_make_room(battle_id, global_position, engines))
	_begin_phase(0, t)
	Events.boss_engaged.emit(t, battle_id)
	if gate != null:
		Events.hud_message.emit(gate_line(), "warn")
	var war := engines_line()   # M9 gate: which of the battle's engines shoot now, which join later
	if war != "":
		Events.hud_message.emit(war, "info")


## M8 release (R1): every encounter of the battle's phases starts the attempt afresh
## (EncounterDirector.p34_reset_encounter: the fallen of an earlier attempt or of a save come back, a cleared
## flag is lifted, living members go home), so an engagement after a load - a death reload, a quit and
## Continue, a travel back, a save written mid-battle - is always a full attempt.
func _fresh_encounters() -> void:
	var d := _director()
	if d == null:
		return
	for enc_id in phase_encounters():
		d.p34_reset_encounter(enc_id)


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


## Phases by the phase fraction - the aggregate with the engines counted whole (each once per attempt; M9 gate,
## lane ironreg: phase_fraction); the guard's break in the last phase.
func _battle_step(tick: int) -> void:
	_recall_despawned()
	if tick % ENGINE_HOLD_CHECK_TICKS == 0:
		_apply_engine_holds()   # M9 gate: an engine that streamed in since
	var frac := phase_fraction()
	var next := phase_index + 1
	while next < phases.size() and (frac <= float(phases[next].get("below", 0.0)) + 1e-6 or _phase_spent()):
		_begin_phase(next, tick)
		next = phase_index + 1
	if phase_index == phases.size() - 1 and guard_broken():
		var c := boss()
		if c != null and c.has_method("p34_yield"):
			c.p34_yield("guard_broken")
	_alert_units(tick)


## M8 screenshot pass (V3): every living, unaware unit of the plan hears the giant (see the notes).
func _alert_units(tick: int) -> void:
	var p := _player()
	if p == null or p.entity == null:
		return
	for uid: String in _planned:
		var e := Sim.get_entity(uid)
		if e == null or not e.is_alive() or e.actor == null or not is_instance_valid(e.actor):
			continue
		var n := e.actor
		var b: Variant = n.get("brain")
		if not (b is EnemyBrain):
			continue
		var brain := b as EnemyBrain
		if brain.aware or brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED,
				EnemyBrain.AIState.DEAD, EnemyBrain.AIState.RETURN]:
			continue
		if (n.has_method("is_held") and bool(n.call("is_held"))) \
				or (n.has_method("is_returning") and bool(n.call("is_returning"))):
			continue
		brain.on_noise(tick, p.global_position, p.entity.entity_id, true)
		if n.has_method("set_lod_tier"):
			n.call("set_lod_tier", 0)


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
	_apply_engine_holds()   # M9 gate: the engines this phase brings shoot from now on
	if i > 0:
		var freed := phase_engines_line(i)
		if freed != "":
			Events.hud_message.emit(freed, "info")


## M9 gate: the phase (0-based) that brings engine `world_id` into the fight - the first phase whose
## encounters name it in their `engines` lists; 0 (the first blow) when none does.
func engine_phase(world_id: String) -> int:
	for i in phases.size():
		for enc_id: Variant in (phases[i] as Dictionary).get("encounters", []):
			for entry: Variant in GameData.get_record(str(enc_id)).get("engines", []):
				if typeof(entry) == TYPE_DICTIONARY and str(entry.get("engine", "")) == world_id:
					return i
	return 0


## M9 gate: while engaged, holds the fire of each of the battle's engines whose phase has not begun and
## frees the rest (see the notes).
func _apply_engine_holds() -> void:
	var d := _director()
	for id in engines:
		var ph := engine_phase(id)
		var hold := state == State.ENGAGED and ph > phase_index
		if hold:
			held_engines[id] = ph
		else:
			held_engines.erase(id)
		var e := d.p32_engine(id) if d != null else null
		if e != null:
			e.set_fire_held(hold)


## M9 gate: the HUD line as the battle engages - how many of its standing engines shoot now and how many
## more a later phase frees ("Smash the ballistae: two shoot now, two more at the Charge.");
## "" when none stands. Engines are counted standing whether or not a crew serves them yet.
func engines_line() -> String:
	var standing: Array = []
	var now := 0
	var later := 0
	var first_later := phases.size()
	for id in engines:
		var e := _standing_engine(id)
		if e == null:
			continue
		standing.append(e)
		var ph := engine_phase(id)
		if ph <= maxi(phase_index, 0):
			now += 1
		else:
			later += 1
			first_later = mini(first_later, ph)
	if standing.is_empty():
		return ""
	if later == 0:
		return "Smash the %s: %s at you." % [engines_noun(standing, now > 1), _n_verb(now, "", "shoot")]
	# Short enough that it and the portcullis's line fit the HUD's three-line message box together.
	var when := mid_sentence(str((phases[first_later] as Dictionary).get("name", "the next phase")))
	if now == 0:
		return "%s %s %s at %s." % [count_word(later).capitalize(), engines_noun(standing, later > 1),
			"open fire" if later > 1 else "opens fire", when]
	return "Smash the %s: %s now, %s more at %s." % [engines_noun(standing, true), _n_verb(now, "", "shoot"),
		count_word(later), when]


## M9 gate: the HUD line as phase `i` (0-based) frees the engines it brings ("Two more ballistae open
## fire."); "" when it frees none that stands.
func phase_engines_line(i: int) -> String:
	var freed: Array = []
	for id in engines:
		var e := _standing_engine(id)
		if e != null and engine_phase(id) == i:
			freed.append(e)
	if freed.is_empty():
		return ""
	return "%s more %s %s." % [count_word(freed.size()).capitalize(), engines_noun(freed, freed.size() > 1),
		"open fire" if freed.size() > 1 else "opens fire"]


## M9 gate: the battle's engine `world_id` while it stands (not wrecked); null otherwise or not loaded.
func _standing_engine(world_id: String) -> SiegeEngine:
	var d := _director()
	var e := d.p32_engine(world_id) if d != null else null
	if e == null or e.destroyed or e.entity == null or not e.entity.is_alive():
		return null
	return e


## M9 gate: what to call `list` of engines - their record's name when they share one ("ballista",
## plural "ballistae"; "catapults"), else "war engines".
static func engines_noun(list: Array, plural: bool) -> String:
	var noun := ""
	for e: Variant in list:
		var n := str((e as SiegeEngine).record.get("display_name", "")).to_lower() if e is SiegeEngine else ""
		if n == "" or (noun != "" and n != noun):
			return "war engines" if plural else "war engine"
		noun = n
	if noun == "":
		return "war engines" if plural else "war engine"
	if not plural:
		return noun
	return noun + ("e" if noun.ends_with("a") else "s")


## M9 gate: "two shoot" / "one shoots", "two more join" / "one more joins" (`more`: "" or "more ").
static func _n_verb(n: int, more: String, verb: String) -> String:
	return "%s %s%s%s" % [count_word(n), more, verb, "s" if n == 1 else ""]


static func count_word(n: int) -> String:
	var words := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
	return words[n] if n >= 0 and n < words.size() else str(n)


## M9 gate: a phase's name inside a sentence ("The Charge" -> "the Charge").
static func mid_sentence(phase_name: String) -> String:
	return "the " + phase_name.substr(4) if phase_name.begins_with("The ") else phase_name


## M9 gate: frees every engine whose fire the battle holds (a reset, a win, the node leaving the tree).
func _free_engine_holds() -> void:
	var d := _director()
	for id in engines:
		var e := d.p32_engine(id) if d != null else null
		if e != null and e.fire_held:
			e.set_fire_held(false)
	held_engines.clear()


## True when every unit the phases begun so far fielded has fallen (or fled): the next phase begins
## then whatever the aggregate says, so a composition whose later phases weigh more than a fraction
## never stalls (the web's smaller formations). M8 release (R1): a unit that will never come - one of a
## cleared encounter that is not up (the director never activates a cleared encounter again) - counts as
## fallen, so no phase waits on it.
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
				if (st == EncounterDirector.UNSPAWNED or st == EncounterDirector.DESPAWNED) and not _unit_spent(d, id):
					return false   # still to come
				var e := Sim.get_entity(id)
				if st == EncounterDirector.SPAWNED and e != null and e.is_alive():
					return false
				fielded += 1
	return fielded > 0


## M8 release (R1): a planned unit that is down for this attempt: dead, or not up in an encounter the
## director holds cleared (it will never be activated again: a load's stale cleared flag).
func _unit_spent(d: EncounterDirector, id: String) -> bool:
	var st := d.member_status(id)
	if st == EncounterDirector.DEAD:
		return true
	return (st == EncounterDirector.UNSPAWNED or st == EncounterDirector.DESPAWNED) \
		and d.encounter_state(str(_unit_encounter.get(id, ""))) == EncounterDirector.CLEARED


## M8 release (R1): a unit of a begun phase that left the world without falling (despawned: a chunk unloading
## under it, a node freed by another hand) comes back to the battle - its encounter is activated again once
## the old node has left the world (it returns at home), as an encounter's next activation brings back its
## despawned members. The battle activates each phase's encounters only as the phase begins, so before this a
## phase waited on such a unit for good, and the bar counted it whole.
func _recall_despawned() -> void:
	var d := _director()
	if d == null:
		return
	for i in range(0, phase_index + 1):
		for enc_id: Variant in phases[i].get("encounters", []):
			if d.encounter_state(str(enc_id)) != EncounterDirector.ACTIVE:
				continue
			for id: String in d.members_of(str(enc_id)):
				if _planned.has(id) and d.member_status(id) == EncounterDirector.DESPAWNED and Sim.get_entity(id) == null:
					d.force_activate(str(enc_id))
					break


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
	_unit_encounter.clear()
	_engine_max.clear()
	var stage := 0
	var p := _player()
	if p != null:
		stage = p.current_growth_stage()
	for ph: Dictionary in phases:
		for enc_id: Variant in ph.get("encounters", []):
			var units := planned_units(GameData.get_record(str(enc_id)), stage, LevelRoot.is_web())
			_planned.merge(units)
			for id: String in units:
				_unit_encounter[id] = str(enc_id)
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


## {"current", "total", "fraction", "phase", "count", "name", "yielded"}: the battle's bar. A unit down for
## this attempt (dead, or one of a cleared encounter that will never come: M8 release, R1) counts nothing.
func aggregate() -> Dictionary:
	var current := _units_current()
	for id: String in _engine_max:
		var e := Sim.get_entity(id)
		if e != null and e.combatant != null and e.is_alive():
			current += e.combatant.pools.health
	return {"current": current, "total": _total, "fraction": current / _total if _total > 0.0 else 0.0,
		"phase": boss_phase(), "count": phase_count(), "name": battle_name, "yielded": surrendered}


func aggregate_fraction() -> float:
	return float(aggregate().fraction)


## M9 gate (lane ironreg): the fraction the phases follow - the aggregate with every engine of the battle counted
## at its full health, wrecked or worn or not: (the units' current health + the engines' maxima) / the total. It is
## the bar's fraction while the engines stand whole, so each phase's `below` keeps its meaning (the layout's 0.7
## and 0.5, set with the four ballistae standing: the Charge as the Wall falls, the Last Stand as the riders do) -
## but a ballista broken on the way to the gate, in an earlier attempt (its wreck persists and its health stays in
## the total) or mid-fight no longer brings a phase on early. The bar the giant sees still counts what the engines
## have left, so smashing them shows there.
func phase_fraction() -> float:
	if _total <= 0.0:
		return 0.0
	var engines_full := 0.0
	for v: float in _engine_max.values():
		engines_full += v
	return (_units_current() + engines_full) / _total


## The health the planned units have now: a spawned unit its current health (nothing once dead), a unit still to
## come its full health, a unit down for this attempt (M8 release, R1) nothing.
func _units_current() -> float:
	var current := 0.0
	var d := _director()
	for id: String in _planned:
		var e := Sim.get_entity(id)
		if e != null and e.combatant != null:
			current += e.combatant.pools.health if e.is_alive() else 0.0
		elif d == null or not _unit_spent(d, id):
			current += float(_planned[id])
	return current


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


## M8 gate fix-up 1 (N4.5): the line when the battle engages behind its gate. Fort Aldmere's portcullis
## drops behind the giant (P36: on purpose), and the curtain wall is 12 m high: the bailey has no way out
## on foot until the battle ends (death, victory, or Load last checkpoint), so its leaving lines above are
## reached only by leaving some other way - the giant is told so at once.
func gate_line() -> String:
	return "The portcullis drops behind you: no way out until %s is beaten." % TextUtil.mid_sentence(battle_name)


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
	_free_engine_holds()   # M9 gate


## The battle is over (won, or its commander slain): the room its plan reserved is released (F9).
func _defeat(tick: int) -> void:
	super(tick)
	var d := _director()
	if d != null:
		d.p34_release(battle_id)
	_free_engine_holds()   # M9 gate


func debug_lines() -> PackedStringArray:
	var a := aggregate()
	return PackedStringArray(["BATTLE %s  %s  %d / %d  phase %d/%d%s" % [battle_id, state_name(),
		int(a.current), int(a.total), int(a.phase), int(a.count), "  (surrendered)" if surrendered else ""]])
