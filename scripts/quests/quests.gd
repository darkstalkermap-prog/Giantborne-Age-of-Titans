extends Node
## Quests (autoload "Quests"; plan §3.15, §4.5, §4.6; after GameSession in the autoload order):
## data-driven quests, the active dialogue session, the tutorial director and the slice's end.
##
## Active only in the campaign (GameSession.is_campaign(): the Valley and, P20, the world) or while
## a test sets test_active; the sandbox has no quests and no tutorial (decision 28). Dialogue works
## anywhere.
##
## P20 (plan M6-M9 §2.6, §2.12): quests run on every campaign level - a stage that names another
## level's targets simply waits, and objective positions fall back to the level's world index when
## the node is not loaded; a stage may name several `markers` (the objective lists them all, its
## position is the one nearest the giant); `xp_floor_level` lifts a stage's XP award to at least
## what reaches that level; `waiting_text` is carried for the journal (P27); the condition context
## carries the campaign level, the giant's position, its ancestry and whether it was chosen
## (count, quest_done, level_is, ancestry_is, ancestry_chosen); dialogue's attribute_points
## effect adds unspent attribute points; and the M6-M9 tutorial events (poi_discovered,
## region_changed, formation_changed, size_gate_blocked, level_entered, ability_evolved) reach the
## tutorial director.
##
## Quests. `quest` records run in stage order, and every condition reads world state (kills,
## flags, destroyed objects, items, stage, level; §4.5), so a goal reached early completes as
## soon as its stage comes up, in the same evaluation. The state lives in WorldState flags, so a
## checkpoint saves it and a reload rolls it back with everything else:
##   quest.<short id>.stage   the current stage id (the last one once complete)
##   quest.<short id>.done    true when complete, false when abandoned
## An auto_start quest starts at once (New Game); another starts the first time all its
## start_conditions hold (quest_started; its first stage is current); abandon_when ends an active
## quest without rewards (quest_abandoned).
## A completed stage grants its rewards once, gated by try_set_flag("reward.<short id>.<stage>"):
## xp (Events.xp_award_requested(xp, "quest:<id>:<stage>")), items (WorldState.add_item) and
## set_flags (first write wins); then the next stage starts (quest_stage_changed; GameSession
## takes a checkpoint for quest.main stages). After the last stage: quest.<short id>.done = true,
## quest_completed, and on_complete_flags (first write wins). When "slice.completed" becomes
## true, slice_completed is emitted and the end screen is requested.
## The evaluation runs from a Sim POST_RESOLVE hook (order 100) every EVALUATE_EVERY_TICKS ticks
## and on the next tick after a relevant event; evaluate_now() runs it at once. Nothing completes
## while the player is dead (a reload follows).
##
## Memory of the current level (reset when a new player appears - a reload - and in tests):
## areas entered ("entered" holds while the player is inside an area, or once it entered it
## since the level loaded), deaths and destructions seen, and hits_on counters (the player's
## blows that connected - HIT, BLOCKED, PARRIED, GUARD_BROKEN - per target and action). They
## reset on a reload, which plan §3.15 accepts.
##
## Dialogue. dialogue_requested(npc_id, dialogue_id) (NpcTalker) -> start_dialogue() and the
## dialogue screen (ui_screen_requested("dialogue", {"session"})). start_dialogue() replaces any
## running session; `dialogue` is the running DialogueSession (null when none): the screen and the
## Valley bot share it. Dialogue rewards teach abilities through the player's
## progression.learn_ability(id, "reward").
##
## Objectives. objectives() lists the active quests' current stages - quest.main first, then the
## side quests (tracker_priority, then quests started by conditions before auto-started ones,
## then id descending: a village branch before quest.village before quest.tutorial);
## current_objective() is the first of them. Each is {"quest_id", "stage_id", "text", "kind" (the
## complete_when type), "marker_id", "position" (the marker, else the first target found in the
## level; Vector3.INF when none), "targets", "bot", "title", "main", "stage_index", "stage_count"}.
## M7 polish (the M7 gate review): "markers" are the stage's open markers (a marker whose
## markers_done_when condition holds - an oath lead whose oath is won - is dropped), and a marker or
## target that another campaign level holds leads to this level's door there (objective_route:
## "position" is the exit's, "via_exit", "via_name" and "via_text" name it; "" when the objective is
## on this level). M8 gate (F46): of a multi-marker stage's open markers, "position" is the nearest one
## the giant's stage can reach (marker_min_stage: a POI's min_stage), else the nearest, and
## "marker_id" names that marker ("markers" and "positions" still list every open one). M8 gate (F29): a
## stage's `lead` (stage_lead) replaces them while it holds - the way round a gate the giant's stage
## cannot pass yet - and "via_text" is its text ("by the Ironway"); "lead" is true then.

const MAIN_QUEST_ID := "quest.main"
const HOOK_ORDER := 100
const EVALUATE_EVERY_TICKS := 10
## More quest changes than this in one evaluation means a loop in the data.
const MAX_CHANGES := 64
const SLICE_FLAG := "slice.completed"
const OUTCOME_FLAG := "quest.village.outcome"
const PROGRESSION_ID := "progression.default"
const DEFAULT_PACING_LABEL := "Prototype pacing: accelerated quest XP"
const MAX_HISTORY := 200
## Shown when a talker's conversation cannot start (no record, or no entry holds).
const NOTHING_TO_SAY := "They have nothing to say right now."
## A position lookup that found nothing is retried after this many ticks.
const MISS_RETRY_TICKS := 60

const INACTIVE := "inactive"
const ACTIVE := "active"
const COMPLETED := "completed"
const ABANDONED := "abandoned"

## Hit outcomes that count for hits_on (the blow connected).
const COUNTED_OUTCOMES := [HitResult.Outcome.HIT, HitResult.Outcome.BLOCKED, HitResult.Outcome.PARRIED,
	HitResult.Outcome.GUARD_BROKEN]

## The running conversation (null when none). The dialogue screen and the Valley bot share it.
var dialogue: DialogueSession = null
## The tutorial prompts (driven from here while quests are active).
var tutorial := TutorialDirector.new()
## Tests turn quests on outside the Valley.
var test_active := false
## Tests and tools: when not empty, only these quest ids run and are listed (fixtures stay apart
## from the shipped quests).
var scope := PackedStringArray()
## The quest listed first and tracked as the main one (tests may point it at a fixture).
var main_quest_id := MAIN_QUEST_ID
## Quest changes of this process, oldest first: {"tick", "quest_id", "event", "stage"} with event
## started | stage | completed | abandoned | reward (last MAX_HISTORY).
var history: Array = []

var _dirty := true
var _last_eval_tick := -1000000
var _player_iid := 0
var _entered := {}      ## area id -> true (entered since the level loaded)
var _died := {}         ## entity id -> true
var _destroyed := {}    ## world id -> true
var _hits := {}         ## target id -> {action id -> count}
var _hit_kinds := {}    ## action id -> kind
var _positions := {}    ## "marker:" / "area:" / "prop:" + id -> Vector3, per level
var _misses := {}       ## the same keys -> the tick a lookup found nothing


func _ready() -> void:
	add_to_group("debug_info_providers")
	tutorial.setup(condition_context, _player_or_null)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_post_resolve, HOOK_ORDER)
	for pair: Array in _listeners():
		(pair[0] as Signal).connect(pair[1])


func _listeners() -> Array:
	return [
		[Events.flag_changed, _on_flag_changed],
		[Events.entity_died, _on_entity_died],
		[Events.object_destroyed, _on_object_destroyed],
		[Events.object_opened, _on_world_event3],
		[Events.item_added, _on_item_event],
		[Events.item_removed, _on_item_event],
		[Events.area_entered, _on_area_entered],
		[Events.area_exited, _on_world_event3],
		[Events.encounter_cleared, _on_world_event2],
		[Events.growth_changed, _on_growth_changed],
		[Events.level_changed, _on_world_event3],
		[Events.weapon_equipped, _on_world_event3],
		[Events.dialogue_outcome, _on_world_event3],
		[Events.dialogue_requested, _on_dialogue_requested],
		[Events.slice_completed, _on_slice_completed],
		[Events.checkpoint_loaded, _on_checkpoint_loaded],
		[Events.hit_resolved, _on_hit_resolved],
		# tutorial events (plan §2.8.1 TUTORIAL_EVENTS)
		[Events.camera_mode_changed, _on_camera_mode_changed],
		[Events.lock_target_changed, _on_lock_target_changed],
		[Events.ability_started, _on_ability_started],
		[Events.telegraph_started, _on_telegraph_started],
		[Events.staggered, _on_staggered],
		[Events.grab_started, _on_grab_started],
		[Events.boss_phase_changed, _on_boss_phase_changed],
		[Events.interacted, _on_interacted],
		[Events.attributes_changed, _on_attributes_changed],
		[Events.shrine_activated, _on_shrine_activated],
		[Events.encounter_activated, _on_encounter_activated],
		# M6-M9 tutorial events (P20; plan M6-M9 §2.15 TUTORIAL_EVENTS)
		[Events.poi_discovered, _on_poi_discovered],
		[Events.region_changed, _on_region_changed],
		[Events.formation_changed, _on_formation_changed],
		[Events.size_gate_blocked, _on_size_gate_blocked],
		[Events.level_entered, _on_level_entered],
		[Events.ability_evolved, _on_ability_evolved],
	]


## True while quests and tutorials run: in the campaign, or when a test turned them on.
func is_active() -> bool:
	return test_active or GameSession.is_campaign()


## M8 gate fix-up 1 (N4.1): true while a campaign load waits for its level's player
## (GameSession.pending_restore: the title after Continue or New Game, the frames before a death,
## debug or travel reload). The save's character is on no player then, so the hook neither evaluates
## nor updates the tutorial: a stage the loaded save already meets (the growth checkpoint is taken
## before the stage it completes) paid its XP to no listener and set its once-flag for good, and a
## prompt showed at the title. The first tick after on_level_ready evaluates with the restored giant.
## A test that turned quests on itself (test_active) is not held.
func waiting_for_load() -> bool:
	return not test_active and GameSession.pending_restore


# --------------------------------------------------------------------------- records and state

## Every quest record (only those in `scope` when it is set): the main quest first, then by id.
func quest_records() -> Array:
	var out: Array = []
	for rec: Dictionary in GameData.records_of_type("quest"):
		if scope.is_empty() or scope.has(str(rec.get("id", ""))):
			out.append(rec)
	for i in out.size():
		if str((out[i] as Dictionary).get("id", "")) == main_quest_id and i > 0:
			out.push_front(out.pop_at(i))
			break
	return out


func quest_record(quest_id: String) -> Dictionary:
	var rec := GameData.get_record(quest_id)
	return rec if str(rec.get("type", "")) == "quest" else {}


## quest.<short id>.stage (quest.main -> quest.main.stage).
static func stage_flag(quest_id: String) -> String:
	return quest_id + ".stage"


## quest.<short id>.done.
static func done_flag(quest_id: String) -> String:
	return quest_id + ".done"


## The once-flag of a stage's rewards: reward.<short id>.<stage> (reward.main.grove).
static func reward_flag(quest_id: String, stage_id: String) -> String:
	return "reward.%s.%s" % [quest_id.trim_prefix("quest."), stage_id]


## inactive | active | completed | abandoned (from the quest's flags).
func quest_state(quest_id: String) -> String:
	if p37_events.has(quest_id):
		return ACTIVE   # P37: a world event running now is an active objective
	if WorldState.has_flag(done_flag(quest_id)):
		return COMPLETED if QuestConditions.truthy(WorldState.get_flag(done_flag(quest_id))) else ABANDONED
	return ACTIVE if str(WorldState.get_flag(stage_flag(quest_id), "")) != "" else INACTIVE


## The current stage id ("" before the quest started; the last stage once complete).
func stage_of(quest_id: String) -> String:
	var v: Variant = WorldState.get_flag(stage_flag(quest_id), "")
	return str(v) if v != null else ""


func is_complete(quest_id: String) -> bool:
	return quest_state(quest_id) == COMPLETED


## Starts a quest now (tests, tools), whatever its start rule. False when it is unknown or
## already started.
func start_quest(quest_id: String) -> bool:
	var rec := quest_record(quest_id)
	if rec.is_empty() or quest_state(quest_id) != INACTIVE or _stages(rec).is_empty():
		return false
	_start(rec, Sim.tick)
	_dirty = true
	return true


static func _stages(rec: Dictionary) -> Array:
	return rec.get("stages", []) if typeof(rec.get("stages")) == TYPE_ARRAY else []


## The stage record with this id ({} when there is none).
static func stage_record(rec: Dictionary, stage_id: String) -> Dictionary:
	for s: Variant in _stages(rec):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == stage_id:
			return s
	return {}


static func _stage_index(rec: Dictionary, stage_id: String) -> int:
	var stages := _stages(rec)
	for i in stages.size():
		if typeof(stages[i]) == TYPE_DICTIONARY and str(stages[i].get("id", "")) == stage_id:
			return i
	return -1


# --------------------------------------------------------------------------- evaluation

## Evaluates every quest now (and updates the tutorial prompts). Does nothing while inactive.
func evaluate_now() -> void:
	if not is_active():
		return
	_sync_level()
	_evaluate(Sim.tick)
	tutorial.update(Sim.tick)


func _on_post_resolve(tick: int) -> void:
	if not is_active() or waiting_for_load():
		return
	_sync_level()
	if _dirty or tick - _last_eval_tick >= EVALUATE_EVERY_TICKS:
		_evaluate(tick)
	tutorial.update(tick)


func _evaluate(tick: int) -> void:
	_dirty = false
	_last_eval_tick = tick
	_p29_follow_main()   # P29: quest.world_main leads once the Valley's main quest is done
	var p := _player_or_null()
	if p != null and p.entity != null and not p.entity.is_alive():
		return
	var ctx := condition_context()
	for i in MAX_CHANGES:
		var changed := false
		for rec: Dictionary in quest_records():
			if _step(rec, ctx, tick):
				changed = true
				break
		if not changed:
			_dirty = false   # this evaluation already saw its own flag changes
			return
		ctx = condition_context()
	push_warning("Quests: more than %d quest changes in one evaluation; stopped" % MAX_CHANGES)


## One step of one quest: start, abandon or complete its stage. True when something changed.
func _step(rec: Dictionary, ctx: Dictionary, tick: int) -> bool:
	var id := str(rec.get("id", ""))
	if id == "" or _stages(rec).is_empty():
		return false
	match quest_state(id):
		INACTIVE:
			if bool(rec.get("auto_start", false)) or QuestConditions.all_hold(rec.get("start_conditions", []), ctx):
				_start(rec, tick)
				return true
		ACTIVE:
			var abandon: Variant = rec.get("abandon_when")
			if typeof(abandon) == TYPE_DICTIONARY and QuestConditions.holds(abandon, ctx):
				_abandon(rec, tick)
				return true
			var srec := stage_record(rec, stage_of(id))
			if srec.is_empty():
				# The saved stage is not in the data (it changed): start again at the first stage.
				push_warning("Quests: %s has no stage '%s'; back to its first stage" % [id, stage_of(id)])
				_set_stage(id, str((_stages(rec)[0] as Dictionary).get("id", "")), tick)
				return true
			if QuestConditions.holds(srec.get("complete_when"), ctx):
				_complete_stage(rec, srec, tick)
				return true
	return false


## A quest starts at its first stage. Only quest_started announces it: quest_stage_changed is for
## the stages that follow, so GameSession's quest.main checkpoints follow completed stages (New
## Game, where quest.main starts, has just saved its own checkpoint).
func _start(rec: Dictionary, tick: int) -> void:
	var id := str(rec.id)
	var first := str((_stages(rec)[0] as Dictionary).get("id", ""))
	WorldState.set_flag(stage_flag(id), first)
	_log(tick, id, "started", first)
	Events.quest_started.emit(tick, id)


func _set_stage(quest_id: String, stage_id: String, tick: int) -> void:
	WorldState.set_flag(stage_flag(quest_id), stage_id)
	_log(tick, quest_id, "stage", stage_id)
	Events.quest_stage_changed.emit(tick, quest_id, stage_id)


func _complete_stage(rec: Dictionary, srec: Dictionary, tick: int) -> void:
	var id := str(rec.id)
	var sid := str(srec.get("id", ""))
	if WorldState.try_set_flag(reward_flag(id, sid), true):
		_grant(rec, srec, tick)
	var stages := _stages(rec)
	var next_index := _stage_index(rec, sid) + 1
	if next_index >= stages.size():
		_complete_quest(rec, tick)
	else:
		_set_stage(id, str((stages[next_index] as Dictionary).get("id", "")), tick)


## A stage's rewards (called once: the reward flag was set just now).
func _grant(rec: Dictionary, srec: Dictionary, tick: int) -> void:
	var id := str(rec.id)
	var sid := str(srec.get("id", ""))
	var source := "quest:%s:%s" % [id, sid]
	_log(tick, id, "reward", sid)
	var items: Variant = srec.get("items", [])
	if typeof(items) == TYPE_ARRAY:
		for it: Variant in items:
			if typeof(it) == TYPE_DICTIONARY:
				WorldState.add_item(str(it.get("item", "")), int(it.get("count", 1)), source)
	var flags: Variant = srec.get("set_flags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		for f: Variant in (flags as Dictionary).keys():
			WorldState.try_set_flag(str(f), flags[f])
	var xp := stage_award(srec, current_xp())
	if xp > 0:
		Events.xp_award_requested.emit(xp, source)


## The XP a completed stage awards to a character holding `xp_now` (P20): its `xp`, lifted by
## `xp_floor_level` to at least the XP that reaches that level (plan M6-M9 decision 25: a level
## never blocks the main thread).
static func stage_award(srec: Dictionary, xp_now: int) -> int:
	var xp := maxi(0, int(srec.get("xp", 0)))
	var floor_level := int(srec.get("xp_floor_level", 0))
	if floor_level > 1:
		xp = maxi(xp, Progression.xp_for_level(floor_level) - xp_now)
	return xp


## The character's total XP now: the player's progression, else the session character's.
func current_xp() -> int:
	var p := _player_or_null()
	if p != null and p.progression != null:
		return int(p.progression.xp)
	return maxi(0, int(GameSession.character.get("xp", 0)))


func _complete_quest(rec: Dictionary, tick: int) -> void:
	var id := str(rec.id)
	WorldState.set_flag(done_flag(id), true)
	_log(tick, id, "completed", stage_of(id))
	Events.quest_completed.emit(tick, id)
	var flags: Variant = rec.get("on_complete_flags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		for f: Variant in (flags as Dictionary).keys():
			WorldState.try_set_flag(str(f), flags[f])
	# GameSession checkpoints every main stage (quest_stage_changed); the main quest's end is one
	# too, so the slice's completion is saved (in this tick's POST_RESOLVE drain, before the end
	# screen opens). It is a completion checkpoint (P17a, M4 review): aware enemies do not hold it
	# back - the crown can be taken with the wardens still about - and a quit to the title from
	# the end screen commits it if anything else still holds it.
	if id == main_quest_id:
		GameSession.request_checkpoint("quest_complete", "", true)


func _abandon(rec: Dictionary, tick: int) -> void:
	var id := str(rec.id)
	WorldState.set_flag(done_flag(id), false)
	_log(tick, id, "abandoned", stage_of(id))
	Events.quest_abandoned.emit(tick, id)


func _log(tick: int, quest_id: String, event: String, stage: String) -> void:
	history.append({"tick": tick, "quest_id": quest_id, "event": event, "stage": stage})
	if history.size() > MAX_HISTORY:
		history.remove_at(0)


# --------------------------------------------------------------------------- context

## The QuestConditions context now (live WorldState dictionaries, the player's stage, level and
## weapon, the areas the player is inside, and this level's memory).
func condition_context() -> Dictionary:
	var p := _player_or_null()
	return {
		"flags": WorldState.flags, "deltas": WorldState.deltas, "inventory": WorldState.inventory,
		"stage": _stage_of_player(p), "level": _level_of_player(p), "weapon": _weapon_of_player(p),
		"inside": _inside_areas(), "entered": _entered, "died": _died, "destroyed": _destroyed,
		"hits": _hits, "hit_kinds": _hit_kinds,
		# P20 (plan M6-M9 §2.12)
		"level_id": GameSession.current_level_id(),
		"position": p.global_position if p != null and p.is_inside_tree() else Vector3.INF,
		"ancestry": _ancestry_of_player(p), "ancestry_chosen": _ancestry_chosen_of_player(p),
		"position_of": _p29_position_of,   # P29: the near condition's target positions
	}


## The character's ancestry: the progression component's (live), else the session character's.
static func _ancestry_of_player(p: GiantPlayer) -> String:
	if p != null and p.progression != null:
		return str(p.progression.ancestry)
	return str(GameSession.character.get("ancestry", CharacterState.DEFAULT_ANCESTRY))


## Whether the ancestry was chosen: a live `ancestry_chosen` on the progression component when a
## package adds one (P33), else the session character's.
static func _ancestry_chosen_of_player(p: GiantPlayer) -> bool:
	if p != null and p.progression != null and "ancestry_chosen" in p.progression:
		return bool(p.progression.get("ancestry_chosen"))
	return bool(GameSession.character.get("ancestry_chosen", false))


func _player_or_null() -> GiantPlayer:
	var p := GameSession.player()
	return p if p != null and is_instance_valid(p) else null


static func _stage_of_player(p: GiantPlayer) -> int:
	if p != null:
		return p.current_growth_stage()
	return maxi(1, int(GameSession.character.get("growth_stage", 1)))


## The character level: the progression component's (its level also counts while ungated,
## where controller.level stays 99), else the session character's.
static func _level_of_player(p: GiantPlayer) -> int:
	if p != null and p.progression != null:
		return int(p.progression.level)
	var lv := int(GameSession.character.get("level", 1))
	return lv if lv >= 1 and lv < CharacterState.MAX_LEVEL else 1


static func _weapon_of_player(p: GiantPlayer) -> String:
	if p != null:
		return str(p.current_weapon().get("id", ""))
	return str(GameSession.character.get("weapon", ""))


func _inside_areas() -> Dictionary:
	var out := {}
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(AreaTrigger.GROUP):
		var a := n as AreaTrigger
		if a != null and a.player_inside and a.area_id != "":
			out[a.area_id] = true
	return out


## A new player (a level load or a reload) starts a new level memory.
func _sync_level() -> void:
	var p := _player_or_null()
	var iid := p.get_instance_id() if p != null else 0
	if iid != _player_iid:
		_player_iid = iid
		_reset_level_memory()


func _reset_level_memory() -> void:
	_entered.clear()
	_died.clear()
	_destroyed.clear()
	_hits.clear()
	_hit_kinds.clear()
	_positions.clear()
	_misses.clear()
	tutorial.reset()
	_dirty = true


# --------------------------------------------------------------------------- objectives

## The ids of the active quests: quest.main first, then the side quests in tracker order.
func active_quest_ids() -> PackedStringArray:
	var main := false
	var side: Array = []
	for rec: Dictionary in quest_records():
		var id := str(rec.get("id", ""))
		if quest_state(id) != ACTIVE:
			continue
		if id == main_quest_id:
			main = true
		else:
			side.append(rec)
	side.sort_custom(_side_before)
	var out := PackedStringArray()
	if main:
		out.append(main_quest_id)
	for rec: Dictionary in side:
		out.append(str(rec.id))
	return _p37_insert_events(out, main)   # P37: running world events, right after the main quest


static func _side_before(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("tracker_priority", 0))
	var pb := int(b.get("tracker_priority", 0))
	if pa != pb:
		return pa > pb
	var sa := bool(a.get("auto_start", false))
	var sb := bool(b.get("auto_start", false))
	if sa != sb:
		return not sa
	return str(a.get("id", "")) > str(b.get("id", ""))


## The current objective of every active quest (main first), see the header.
func objectives() -> Array:
	var out: Array = []
	for id in active_quest_ids():
		var o := objective_for(id)
		if not o.is_empty():
			out.append(o)
	_p27_mark_tracked(out)   # P27: "tracked" on each
	return out


## The first objective of objectives() ({} when no quest is active). P27: the tracked quest's
## objective (Quests.tracked_id(): the main quest unless the player tracks another).
func current_objective() -> Dictionary:
	var tracked := _p27_tracked_objective()
	if not tracked.is_empty():
		return tracked
	for id in active_quest_ids():
		var o := objective_for(id)
		if not o.is_empty():
			return o
	return {}


## The objective of one active quest ({} when it is not active).
func objective_for(quest_id: String) -> Dictionary:
	if p37_events.has(quest_id):
		return (p37_events[quest_id] as Dictionary).duplicate()   # P37: a running world event's objective
	var rec := quest_record(quest_id)
	if rec.is_empty() or quest_state(quest_id) != ACTIVE:
		return {}
	var sid := stage_of(quest_id)
	var srec := stage_record(rec, sid)
	if srec.is_empty():
		return {}
	var cond: Variant = srec.get("complete_when", {})
	var targets := QuestConditions.targets_of(cond)
	var markers := open_markers(srec)   # M7 polish: a lead whose markers_done_when holds is dropped
	var marker := markers[0] if not markers.is_empty() else ""
	# M7 polish: a marker on another campaign level leads to this level's door there (objective_route);
	# several markers behind one door are one position.
	var positions: Array = []
	var routes: Array = []
	var position_markers: Array = []   # M8 gate (F46): the marker of each position
	for m in markers:
		var r := objective_route(m)
		var mp: Vector3 = r.position
		if mp.is_finite() and not (str(r.via_exit) != "" and positions.has(mp)):
			positions.append(mp)
			routes.append(r)
			position_markers.append(m)
	var route := objective_route(marker, targets)
	var position: Vector3 = route.position
	if markers.size() > 1 and not positions.is_empty():
		# M8 gate (F46): the nearest of the markers the giant's stage can reach (else the nearest of all),
		# and marker_id names the marker that position is.
		var i := positions.find(nearest_to_player(reachable_positions(positions, position_markers)))
		position = positions[i]
		route = routes[i]
		marker = position_markers[i]
	# M8 gate (F29): while the stage's lead holds, the way round a gate the giant cannot pass yet leads.
	# Fix-up 1: past the lead's marker its `then` leads (lead_marker), and only on the lead's own level - on
	# another (the Valley) the route leads to this level's door either way, and the tracker names the door.
	var lead_text := ""
	var lead := stage_lead(srec)
	var led := false
	if not lead.is_empty():
		var lm := lead_marker(lead)
		var lr := objective_route(lm)
		if (lr.position as Vector3).is_finite() and str(lr.via_exit) == "":
			marker = lm
			route = lr
			position = lr.position
			markers = PackedStringArray([marker])
			positions = [position]
			lead_text = str(lead.get("text", ""))
			led = true
	var bot: Dictionary = (srec.get("bot", {}) as Dictionary).duplicate(true) if typeof(srec.get("bot")) == TYPE_DICTIONARY else {}
	return {"quest_id": quest_id, "stage_id": sid, "text": str(srec.get("objective", "")),
		"kind": str(cond.get("type", "")) if typeof(cond) == TYPE_DICTIONARY else "",
		"marker_id": marker, "position": position, "targets": targets,
		"bot": bot, "title": str(rec.get("display_name", quest_id)), "main": quest_id == main_quest_id,
		"stage_index": _stage_index(rec, sid), "stage_count": _stages(rec).size(),
		# P20: every marker of a multi-marker stage and their known positions; the journal's text.
		"markers": markers, "positions": positions, "waiting_text": str(srec.get("waiting_text", "")),
		# M7 polish: the exit the position leads to when the objective lies on another level ("" here),
		# its name and the tracker's and the journal's phrase for it ("by the Kings' Door").
		"via_exit": str(route.via_exit), "via_name": str(route.via_name),
		"via_text": lead_text if lead_text != "" else by_exit_text(str(route.via_name)),
		"lead": led}


## A stage's marker ids: its `marker`, then its `markers` (P20), each once.
static func stage_markers(srec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var m := str(srec.get("marker", ""))
	if m != "":
		out.append(m)
	if typeof(srec.get("markers")) == TYPE_ARRAY:
		for id: Variant in srec.markers:
			var s := str(id)
			if s != "" and not out.has(s):
				out.append(s)
	return out


## The stage's markers that still lead somewhere (M7 polish; the M7 gate review): stage_markers()
## without each one whose `markers_done_when` condition holds now - an oath lead once its oath is
## won - so the objective, its diamonds on the compass and the map, and the compass's leads never
## point at a finished lead (the main thread's oaths stage kept sending a giant who had won
## Brannock's oath back to Brannock's green).
func open_markers(srec: Dictionary) -> PackedStringArray:
	var done: Variant = srec.get("markers_done_when")
	if typeof(done) != TYPE_DICTIONARY or (done as Dictionary).is_empty():
		return stage_markers(srec)
	return markers_open_in(srec, condition_context())


## open_markers() for a condition context (pure): the stage's markers whose markers_done_when
## condition does not hold in `ctx` (a marker without one is always open), in stage order.
static func markers_open_in(srec: Dictionary, ctx: Dictionary) -> PackedStringArray:
	var done: Variant = srec.get("markers_done_when")
	var out := PackedStringArray()
	for m in stage_markers(srec):
		var c: Variant = (done as Dictionary).get(m) if typeof(done) == TYPE_DICTIONARY else null
		if typeof(c) == TYPE_DICTIONARY and QuestConditions.holds(c, ctx):
			continue
		out.append(m)
	return out


## M8 gate (F29): the stage's `lead` while it holds ({} otherwise): the giant's stage is below its
## below_stage and the giant does not stand in its outside_region (the level index's region at its
## position; no region named: anywhere). The main thread's grow6 leads a giant below stage 6 that is not
## yet up in the Stonehold to the Ironway's waystone - the Giant's Stair refuses it, and the Ironway is
## the highlands' long way for every stage (plan §5.5) - and the tracker names "by the Ironway".
func stage_lead(srec: Dictionary) -> Dictionary:
	var lead: Variant = srec.get("lead")
	if typeof(lead) != TYPE_DICTIONARY or str((lead as Dictionary).get("marker", "")) == "":
		return {}
	var p := _player_or_null()
	if _stage_of_player(p) >= int((lead as Dictionary).get("below_stage", 0)):
		return {}
	var region := str((lead as Dictionary).get("outside_region", ""))
	if region != "" and p != null and p.is_inside_tree():
		var idx := level_index()
		var root := _level_root()
		var offset := root.global_position if root != null and root.is_inside_tree() else Vector3.ZERO
		if idx != null and idx.region_at(p.global_position - offset) == region:
			return {}
	return lead


## M8 gate fix-up 1 (N2.3): a lead's `then` leads once the giant is past the lead's marker.
const LEAD_REACH_M := 40.0


## The marker a holding lead points at (M8 gate fix-up 1, N2.3): its marker, or - once the giant is past it
## on the way round (within LEAD_REACH_M of it, or nearer the lead's `then` than the marker is) - its `then`.
## grow6's lead pointed a giant walking up the Ironway back down to the foot's waystone until the Stonehold
## began, 70 m on; now the Ironway's top leads from the foot on.
func lead_marker(lead: Dictionary) -> String:
	var m := str(lead.get("marker", ""))
	var then := str(lead.get("then", ""))
	var p := _player_or_null()
	if then == "" or p == null or not p.is_inside_tree():
		return m
	var at := objective_route(m)
	var nxt := objective_route(then)
	if str(at.via_exit) != "" or str(nxt.via_exit) != "":
		return m
	var a: Vector3 = at.position
	var b: Vector3 = nxt.position
	if not a.is_finite() or not b.is_finite():
		return m
	var g := p.global_position
	if _flat(g, a) <= LEAD_REACH_M or _flat(g, b) < _flat(a, b):
		return then
	return m


## M8 gate (F46): `positions` (of the markers `marker_ids`, in the same order) without those the giant's
## stage cannot reach yet (marker_min_stage above it) - all of them when none is in reach, so a stage
## whose every open marker waits for a bigger giant still leads somewhere.
func reachable_positions(positions: Array, marker_ids: Array) -> Array:
	var stage := _stage_of_player(_player_or_null())
	var out: Array = []
	for i in positions.size():
		if i >= marker_ids.size() or marker_min_stage(str(marker_ids[i])) <= stage:
			out.append(positions[i])
	return out if not out.is_empty() else positions


## M8 gate (F46): the growth stage a giant needs to reach the marker `marker_id`: the highest min_stage
## of this level's world-index POIs whose radius holds the marker (the Drowned Steps' island bell lies in
## the Ancestral Circle, past the stage-5 channel: 5); 0 when none does or the index does not know it.
## The tracker's lead then waits for that stage while a marker the giant can reach is open (the bells'
## quest led a stage-4 giant into the channel's size gate with two wadeable bells still open).
func marker_min_stage(marker_id: String) -> int:
	var idx := level_index()
	if idx == null or marker_id == "":
		return 0
	var at := idx.position_of(marker_id)
	if not at.is_finite():
		return 0
	var need := 0
	for poi: Dictionary in idx.pois.values():
		var c: Vector3 = poi.get("position", Vector3.INF)
		if c.is_finite() and _flat(c, at) <= float(poi.get("radius", 0.0)):
			need = maxi(need, int(poi.get("min_stage", 0)))
	return need


## The position in `positions` nearest the player on the ground plane (the first without one).
func nearest_to_player(positions: Array) -> Vector3:
	var p := _player_or_null()
	if positions.is_empty():
		return Vector3.INF
	if p == null or not p.is_inside_tree():
		return positions[0]
	var best: Vector3 = positions[0]
	var best_d := INF
	for v: Vector3 in positions:
		var d := Vector2(v.x - p.global_position.x, v.z - p.global_position.z).length_squared()
		if d < best_d:
			best_d = d
			best = v
	return best


## Where an objective is: its marker, else the first of its targets found in the level (a living
## entity, an area trigger, a breakable prop); P20: what is not loaded comes from the level's world
## index (the marker's entry, else the first target it knows). Vector3.INF when none is found.
func objective_position(marker_id: String, targets: PackedStringArray = PackedStringArray()) -> Vector3:
	if marker_id != "":
		var m := marker_position(marker_id)
		if m.is_finite():
			return m
	for t in targets:
		var e := Sim.get_entity(t)
		if e != null and e.actor != null and is_instance_valid(e.actor) and (e.actor as Node3D).is_inside_tree():
			return (e.actor as Node3D).global_position
		var a := _cached_position("area:" + t)
		if a.is_finite():
			return a
		var prop := _cached_position("prop:" + t)
		if prop.is_finite():
			return prop
	var idx := level_index()
	if idx != null:
		var root := _level_root()
		var offset := root.global_position if root != null and root.is_inside_tree() else Vector3.ZERO
		if marker_id != "":
			var im := idx.position_of(marker_id)
			if im.is_finite():
				return im + offset
		for t in targets:
			var it := idx.position_of(t)
			if it.is_finite():
				return it + offset
	return Vector3.INF


# --------------------------------------------------------------------------- M7 polish: objectives on another level

## How far from an exit the stone it shares a passage with may stand (the stone the other level's
## exits bring a giant back to: 7-22 m from each door of the Valley and the world).
const PASSAGE_STONE_M := 40.0


## Where an objective leads the giant on the level being played (M7 polish; the M7 gate review):
## {"position", "via_exit", "via_name", "level"}. objective_position() when this level knows the
## marker or a target ("via_exit" ""); else, when another campaign level's index knows it, the exit
## of this level that leads there best (exit_toward), so the HUD marker, the compass and the map lead
## to the Kings' Door or the Broken Stair and the tracker names it. Before, such an objective had
## no position at all (Vector3.INF): quest.sealed_citadel tracked in the world, or the world's main
## thread while the giant revisits the Valley, showed text alone. Position INF and "" when no level
## the exits reach knows it. objective_position() stays this level's own: the near condition reads
## it and must never hold beside a door.
func objective_route(marker_id: String, targets: PackedStringArray = PackedStringArray()) -> Dictionary:
	var pos := objective_position(marker_id, targets)
	if pos.is_finite():
		return {"position": pos, "via_exit": "", "via_name": "", "level": ""}
	var ids := PackedStringArray()
	if marker_id != "":
		ids.append(marker_id)
	ids.append_array(targets)
	for id in ids:
		var r := exit_toward(id)
		if str(r.via_exit) != "":
			return r
	return {"position": Vector3.INF, "via_exit": "", "via_name": "", "level": ""}


## The exit of the level being played that leads best toward `id` on another level:
## {"position" (this level's space), "via_exit", "via_name", "level"} ("" and INF when none). Among
## the open exits (exit_open) to a level whose index knows `id`, the one with the shortest way in a
## straight line: from the giant to the exit, plus from the stone the exit arrives at to `id`.
func exit_toward(id: String) -> Dictionary:
	var out := {"position": Vector3.INF, "via_exit": "", "via_name": "", "level": ""}
	var idx := level_index()
	if idx == null or idx.exits.is_empty() or id == "":
		return out
	var root := _level_root()
	var offset := root.global_position if root != null and root.is_inside_tree() else Vector3.ZERO
	var p := _player_or_null()
	var at := p.global_position - offset if p != null and p.is_inside_tree() else Vector3.INF
	var best := INF
	var ids: Array = idx.exits.keys()
	ids.sort()
	for eid: Variant in ids:
		var e: Dictionary = idx.exits[eid]
		var to_level := str(e.get("to_level", ""))
		if to_level == "" or to_level == idx.level_id:
			continue
		var there := WorldIndex.for_level(to_level)
		var target := there.position_of(id) if there != null else Vector3.INF
		if not target.is_finite() or not exit_open(idx, str(eid), there):
			continue
		var door: Vector3 = e.get("position", Vector3.INF)
		var arrival := there.position_of(str(e.get("to_checkpoint", "")))
		var cost := _flat(arrival, target) if arrival.is_finite() else 0.0
		if at.is_finite():
			cost += _flat(at, door)
		if cost < best:
			best = cost
			out = {"position": door + offset, "via_exit": str(eid),
				"via_name": str(e.get("display_name", idx.display_name(str(eid)))), "level": to_level}
	return out


## Whether a giant may pass the exit `exit_id` of the level `idx` (`there`: the index of the level it
## leads to) now. A door is a passage with a stone at each end: the stone it arrives at and the stone
## beside it on this side - the checkpoint the other level's exits bring a giant back to, nearest the
## exit within PASSAGE_STONE_M - must both have their requires_flags, and its LevelExit node, while
## it is loaded, its own. (The Citadel stair stands behind the sealed gate with no flag of its own; its
## stone opens with the breach, as the Broken Stair's rubble does.)
func exit_open(idx: WorldIndex, exit_id: String, there: WorldIndex) -> bool:
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(LevelExit.GROUP):
			var x := n as LevelExit
			if x != null and x.exit_id == exit_id and not x.is_open():
				return false
	var e: Dictionary = idx.exits.get(exit_id, {})
	if there == null or not _checkpoint_open(there, str(e.get("to_checkpoint", ""))):
		return false
	var door: Vector3 = e.get("position", Vector3.INF)
	var beside := ""
	var nearest := PASSAGE_STONE_M
	for back: Dictionary in there.exits.values():
		if str(back.get("to_level", "")) != idx.level_id:
			continue
		var stone := str(back.get("to_checkpoint", ""))
		var d := _flat(idx.position_of(stone), door) if idx.has_checkpoint(stone) else INF
		if d <= nearest:
			nearest = d
			beside = stone
	return beside == "" or _checkpoint_open(idx, beside)


## True when the checkpoint `id` of `idx` exists and every one of its requires_flags holds.
static func _checkpoint_open(idx: WorldIndex, id: String) -> bool:
	if not idx.has_checkpoint(id):
		return false
	for f: Variant in idx.checkpoint(id).get("requires_flags", PackedStringArray()):
		if not QuestConditions.truthy(WorldState.get_flag(str(f))):
			return false
	return true


## The phrase for the door an objective on another level leads through: "by the Kings' Door" for
## "The Kings' Door" ("" for "").
static func by_exit_text(exit_name: String) -> String:
	if exit_name == "":
		return ""
	return "by " + ("the " + exit_name.substr(4) if exit_name.begins_with("The ") else exit_name)


static func _flat(a: Vector3, b: Vector3) -> float:
	if not a.is_finite() or not b.is_finite():
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()


## The world index of the level being played (P20): the loaded LevelRoot's, else the campaign
## level's; null when there is none.
func level_index() -> WorldIndex:
	var root := _level_root()
	if root != null:
		var idx := root.index()
		if idx != null:
			return idx
	return WorldIndex.for_level(GameSession.current_level_id())


func _level_root() -> LevelRoot:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot


## The position of the objective marker (LevelMarker) with this id, Vector3.INF when none.
func marker_position(marker_id: String) -> Vector3:
	return _cached_position("marker:" + marker_id)


## Forgets the cached marker, trigger and prop positions (a level built in code by a tool or test).
func refresh_positions() -> void:
	_positions.clear()
	_misses.clear()


## Positions of static level nodes, cached for this level (markers, triggers, props never move).
## A miss is looked up again at most once per second.
func _cached_position(key: String) -> Vector3:
	if _positions.has(key):
		return _positions[key]
	if Sim.tick - int(_misses.get(key, -1000000)) < MISS_RETRY_TICKS:
		return Vector3.INF
	var pos := Vector3.INF
	if is_inside_tree():
		var kind := key.get_slice(":", 0)
		var id := key.substr(kind.length() + 1)
		match kind:
			"marker":
				var root := get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot
				var n: Node3D = root.marker(id) if root != null else null
				if n == null:
					for m in get_tree().get_nodes_in_group(LevelMarker.GROUP):
						if m is LevelMarker and (m as LevelMarker).marker_id == id:
							n = m
							break
				if n != null and n.is_inside_tree():
					pos = n.global_position
			"area":
				for a in get_tree().get_nodes_in_group(AreaTrigger.GROUP):
					if a is AreaTrigger and (a as AreaTrigger).area_id == id and (a as Node3D).is_inside_tree():
						pos = (a as Node3D).global_position
						break
			"prop":
				for b in get_tree().get_nodes_in_group("breakables"):
					if b is Node3D and "world_id" in b and str(b.get("world_id")) == id and (b as Node3D).is_inside_tree():
						pos = (b as Node3D).global_position
						break
	if pos.is_finite():
		_positions[key] = pos
		_misses.erase(key)
	else:
		_misses[key] = Sim.tick
	return pos


# --------------------------------------------------------------------------- dialogue

## Starts `dialogue_id` with `npc_id`, ending any running session first. Returns the session
## (also in `dialogue`), or null when the dialogue does not exist or no entry holds.
func start_dialogue(dialogue_id: String, npc_id: String = "") -> DialogueSession:
	end_dialogue()
	var rec := GameData.get_record(dialogue_id)
	if str(rec.get("type", "")) != "dialogue":
		push_warning("Quests: no dialogue record '%s'" % dialogue_id)
		return null
	var s := DialogueSession.new()
	s.ended.connect(_on_session_ended)
	s.attribute_granter = _grant_attribute_points
	dialogue = s
	if not s.begin(rec, npc_id, condition_context, _learn_ability):
		s.ended.disconnect(_on_session_ended)
		dialogue = null
		return null
	return s


## Ends the running conversation (dialogue_ended), if any.
func end_dialogue() -> void:
	if dialogue != null:
		dialogue.end("closed")
	dialogue = null


func _on_session_ended(session: DialogueSession) -> void:
	if dialogue == session:
		dialogue = null
	_dirty = true


## The dialogue effect attribute_points (P20): unspent points to the player's progression (else the
## session character), attributes_changed and a HUD line.
func _grant_attribute_points(points: int, _source: String) -> void:
	if points <= 0:
		return
	var p := _player_or_null()
	if p != null and p.progression != null:
		p.progression.unspent_attribute_points += points
	else:
		GameSession.character["unspent_attribute_points"] = int(GameSession.character.get("unspent_attribute_points", 0)) + points
	Events.attributes_changed.emit(Sim.tick)
	Events.hud_message.emit("+%d attribute point%s" % [points, "" if points == 1 else "s"], "good")


func _learn_ability(action_id: String, source: String) -> bool:
	var p := _player_or_null()
	if p == null or p.progression == null:
		push_warning("Quests: no player progression to teach %s" % action_id)
		return false
	return bool(p.progression.learn_ability(action_id, source))


func _on_dialogue_requested(npc_id: String, dialogue_id: String) -> void:
	var s := start_dialogue(dialogue_id, npc_id)
	if s != null:
		Events.ui_screen_requested.emit("dialogue", {"session": s, "npc_id": npc_id, "dialogue_id": dialogue_id})
	else:
		Events.hud_message.emit(NOTHING_TO_SAY, "info")


# --------------------------------------------------------------------------- tutorial

## The prompt on screen ({"id", "text", "priority", "shown_tick", "progress", "needed", ...}),
## or {} when none is.
func current_tutorial() -> Dictionary:
	return tutorial.current_prompt()


## M8 gate (F28): a new giant's level memory is reset before its first event is recorded - main.gd's
## loading gate emits level_entered while the tree is paused, before the level's first tick, whose
## _sync_level() then wiped the arrival's and the map's prompts (they never showed on a New Game in the
## world nor through the Kings' Door).
func _tutorial_event(event_name: String, info: Dictionary, tick: int = -1) -> void:
	if not is_active() or waiting_for_load():
		return
	_sync_level()
	tutorial.on_event(event_name, info, tick if tick >= 0 else Sim.tick)


func _player_entity_id() -> String:
	var p := _player_or_null()
	return p.entity.entity_id if p != null and p.entity != null else "player"


func _on_camera_mode_changed(mode: int) -> void:
	_tutorial_event("camera_mode_changed", {"mode": mode})


func _on_lock_target_changed(actor_id: String, target_id: String, reason: String) -> void:
	_tutorial_event("lock_target_changed", {"actor": actor_id, "target": target_id, "reason": reason})


func _on_ability_started(tick: int, actor_id: String, action_id: String, _instance_id: int) -> void:
	if not is_active():
		return
	var a := GameData.get_action(action_id)
	_tutorial_event("ability_started", {"actor": actor_id, "action_id": action_id,
		"action_kind": a.kind if a != null else ""}, tick)


func _on_telegraph_started(tick: int, actor_id: String, action_id: String, target_id: String,
		_shape: String, _origin: Vector3, _yaw: float, _radius: float, _length: float, _duration_s: float) -> void:
	if not is_active():
		return
	var a := GameData.get_action(action_id)
	var e := Sim.get_entity(actor_id)
	var archetype := ""
	if e != null and e.combatant != null:
		archetype = str(e.combatant.base_record.get("archetype", ""))
	_tutorial_event("telegraph_started", {"actor": actor_id, "action_id": action_id, "target": target_id,
		"tags": Array(a.tags) if a != null else [], "archetype": archetype}, tick)


func _on_staggered(tick: int, entity_id: String, duration_s: float, reason: String) -> void:
	if not is_active():
		return
	var info := {"entity": entity_id, "duration_s": duration_s, "reason": reason, "distance": INF,
		"grabbable": false}
	var e := Sim.get_entity(entity_id)
	var p := _player_or_null()
	if e != null and p != null and e != p.entity and e.actor != null and is_instance_valid(e.actor):
		var d := (e.actor as Node3D).global_position - p.global_position
		d.y = 0.0
		info.distance = d.length()
		if e.actor.has_method("can_be_grabbed") and bool(e.actor.call("can_be_grabbed")):
			info.grabbable = p.grab == null or p.grab.check_target(e, "hold", "", maxf(float(info.distance), 0.0) + 0.01) == ""
	_tutorial_event("staggered", info, tick)


func _on_grab_started(tick: int, holder_id: String, target_id: String) -> void:
	_tutorial_event("grab_started", {"actor": holder_id, "target": target_id}, tick)


func _on_boss_phase_changed(tick: int, boss_id: String, phase: int) -> void:
	_tutorial_event("boss_phase_changed", {"actor": boss_id, "phase": phase}, tick)


func _on_interacted(tick: int, actor_id: String, interact_id: String) -> void:
	_tutorial_event("interacted", {"actor": actor_id, "interact_id": interact_id}, tick)


func _on_attributes_changed(tick: int) -> void:
	_tutorial_event("attributes_changed", {}, tick)


func _on_shrine_activated(tick: int, shrine_id: String) -> void:
	_tutorial_event("shrine_activated", {"shrine": shrine_id}, tick)


func _on_encounter_activated(tick: int, encounter_id: String) -> void:
	_dirty = true
	_tutorial_event("encounter_activated", {"encounter": encounter_id}, tick)


# M6-M9 tutorial events (P20): each also re-evaluates the quests on the next tick.
func _on_poi_discovered(tick: int, poi_id: String) -> void:
	_dirty = true
	_tutorial_event("poi_discovered", {"poi": poi_id}, tick)


func _on_region_changed(tick: int, region_id: String, previous_id: String) -> void:
	_dirty = true
	_tutorial_event("region_changed", {"region": region_id, "previous": previous_id}, tick)


func _on_formation_changed(tick: int, formation_id: String, state: String) -> void:
	_tutorial_event("formation_changed", {"formation": formation_id, "state": state}, tick)


func _on_size_gate_blocked(tick: int, gate_id: String, min_stage: int, message: String) -> void:
	_tutorial_event("size_gate_blocked", {"gate": gate_id, "min_stage": min_stage, "message": message}, tick)


func _on_level_entered(tick: int, level_id: String, reason: String) -> void:
	_sync_level()   # M8 gate (F28): see _tutorial_event
	_dirty = true
	_tutorial_event("level_entered", {"level": level_id, "reason": reason}, tick)


func _on_ability_evolved(tick: int, from_id: String, to_id: String, slot_key: String) -> void:
	_tutorial_event("ability_evolved", {"from": from_id, "to": to_id, "slot": slot_key}, tick)


# --------------------------------------------------------------------------- world events

func _on_flag_changed(tick: int, flag_id: String, value: Variant) -> void:
	_dirty = true
	if flag_id == SLICE_FLAG and QuestConditions.truthy(value) and is_active():
		Events.slice_completed.emit(tick)


func _on_entity_died(_tick: int, entity_id: String, _killer_id: String) -> void:
	_sync_level()
	_died[entity_id] = true
	_dirty = true


func _on_object_destroyed(_tick: int, world_id: String, _by: String) -> void:
	_sync_level()
	_destroyed[world_id] = true
	_dirty = true


func _on_area_entered(_tick: int, area_id: String, _entity_id: String) -> void:
	_sync_level()
	_entered[area_id] = true
	_dirty = true


func _on_item_event(_tick: int, _item_id: String, _count: int, _why: String) -> void:
	_dirty = true


func _on_growth_changed(_tick: int, _entity_id: String, _old: int, _new: int) -> void:
	_dirty = true


func _on_world_event2(_a: Variant, _b: Variant) -> void:
	_dirty = true


func _on_world_event3(_a: Variant, _b: Variant, _c: Variant) -> void:
	_dirty = true


func _on_hit_resolved(tick: int, r: HitResult) -> void:
	if not is_active() or r == null or r.event == null:
		return
	_tutorial_event("hit_resolved", {"defender": r.event.target_id, "attacker": r.event.attacker_id,
		"outcome": r.outcome_name(), "action_id": r.event.action_id}, tick)
	if r.event.attacker_id != _player_entity_id() or not COUNTED_OUTCOMES.has(r.outcome):
		return
	_sync_level()
	var target := r.event.target_id
	var action_id := r.event.action_id
	var per: Dictionary = _hits.get(target, {})
	per[action_id] = int(per.get(action_id, 0)) + 1
	_hits[target] = per
	if not _hit_kinds.has(action_id):
		var a := GameData.get_action(action_id)
		_hit_kinds[action_id] = a.kind if a != null else ""
	_dirty = true


func _on_checkpoint_loaded(_tick: int, _checkpoint_id: String, _source: String) -> void:
	_reset_level_memory()


# --------------------------------------------------------------------------- the end

func _on_slice_completed(_tick: int) -> void:
	if not is_active():
		return
	Events.ui_screen_requested.emit("end", end_summary())


## What the end screen shows: {"time_s", "deaths", "level", "stage", "outcome"}.
func end_summary() -> Dictionary:
	var p := _player_or_null()
	return {"time_s": float(GameSession.stats.get("play_time_s", 0.0)),
		"deaths": int(GameSession.stats.get("deaths", 0)), "level": _level_of_player(p),
		"stage": _stage_of_player(p), "outcome": str(WorldState.get_flag(OUTCOME_FLAG, ""))}


## True when XP of this source is accelerated quest XP (the tracker shows the pacing label):
## quests with prototype_pacing and dialogue rewards.
func paced_source(source: String) -> bool:
	if source.begins_with("dialogue:"):
		return true
	if not source.begins_with("quest:"):
		return false
	var quest_id := source.get_slice(":", 1)
	return bool(quest_record(quest_id).get("prototype_pacing", false))


## "Prototype pacing: accelerated quest XP" (progression.default.prototype_xp_label).
func pacing_label() -> String:
	var label := str(GameData.get_record(PROGRESSION_ID).get("prototype_xp_label", ""))
	return label if label != "" else DEFAULT_PACING_LABEL


# --------------------------------------------------------------------------- debug and tests

## Lines for the F3 debug panel (group debug_info_providers).
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if not is_active():
		return lines
	var parts := PackedStringArray()
	for id in active_quest_ids():
		parts.append("%s:%s" % [id.trim_prefix("quest."), stage_of(id)])
	var tut := str(tutorial.current.get("id", "-")) if not tutorial.current.is_empty() else "-"
	lines.append("QUESTS %s  tutorial %s  dialogue %s" % [", ".join(parts) if not parts.is_empty() else "-",
		tut, dialogue.dialogue_id if dialogue != null else "-"])
	return lines


## ResetHooks.BEFORE_EACH: quests off, no session, no memory, no tutorial prompt, no history, no
## scopes.
func reset_for_tests() -> void:
	test_active = false
	scope = PackedStringArray()
	main_quest_id = MAIN_QUEST_ID
	tutorial.scope = PackedStringArray()
	if dialogue != null:
		if dialogue.ended.is_connected(_on_session_ended):
			dialogue.ended.disconnect(_on_session_ended)
		dialogue.active = false
	dialogue = null
	_player_iid = 0
	_last_eval_tick = -1000000
	_reset_level_memory()
	tutorial.shown_ids.clear()
	history.clear()
	_p27_reset()
	p37_events.clear()   # P37


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P27
# --- the tracked quest (P27; plan M6-M9 §2.12, §3.10 design 4) -------------------------------------
# The objective marker, the compass and the tracker follow one quest: tracked_quest_id while that
# quest is active, else the main quest while it is active, else the first active quest
# (tracked_id()). GameSession saves tracked_quest_id as progress.tracked_quest and puts it back on
# load (P20), so it survives a save, a death and a fast travel. track_next() (T / D-pad Left) cycles
# the active quests in tracker order; the journal's "Track" calls track(). current_objective() is the
# tracked quest's (one hook line), objectives() marks it ("tracked"), and while another quest is
# tracked the main quest's current markers are the compass's leads (at most LEAD_LIMIT: the oath
# leads of the main thread's multi-marker stage, P29).

## The most leads the compass shows (plan §2.14: up to 3 oath leads).
const LEAD_LIMIT := 3

## The quest the player chose to follow ("" = none chosen: the main quest leads). Saved by GameSession.
var tracked_quest_id := ""


## Tracks an active quest: tracked_quest_id and Events.quest_tracked. False when it is not active.
func track(quest_id: String) -> bool:
	if quest_id == "" or quest_state(quest_id) != ACTIVE:
		return false
	var changed := tracked_id() != quest_id or tracked_quest_id != quest_id
	tracked_quest_id = quest_id
	if changed:
		Events.quest_tracked.emit(quest_id)
	return true


## Tracks the next active quest in tracker order (main first), wrapping; returns it ("" when no
## quest is active).
func track_next() -> String:
	var ids := active_quest_ids()
	if ids.is_empty():
		return ""
	var i := ids.find(tracked_id())
	var next := ids[(i + 1) % ids.size()]
	track(next)
	return next


## The quest followed now: tracked_quest_id while active, else the main quest while active, else the
## first active quest ("" when none is active).
func tracked_id() -> String:
	var ids := active_quest_ids()
	if tracked_quest_id != "" and ids.has(tracked_quest_id):
		return tracked_quest_id
	if ids.has(main_quest_id):
		return main_quest_id
	return ids[0] if not ids.is_empty() else ""


## The tracked quest's objective (objective_for; {} when no quest is active).
func tracked_objective() -> Dictionary:
	var id := tracked_id()
	return objective_for(id) if id != "" else {}


## The compass's leads while another quest is tracked: the main quest's current markers that have
## a position, at most LEAD_LIMIT: [{"marker_id", "position", "via_exit"}] ([] while the main quest
## is the tracked one or is not active). M7 polish: only the open markers (a lead whose oath is won is
## gone), and a marker on another level gives the position of the door there (objective_route; leads
## behind the same door are one).
func leads() -> Array:
	var out: Array = []
	var tracked := tracked_id()
	if tracked == "" or tracked == main_quest_id or quest_state(main_quest_id) != ACTIVE:
		return out
	var o := objective_for(main_quest_id)
	var markers: PackedStringArray = o.get("markers", PackedStringArray())   # M7 polish: the open ones
	var taken: Array = []
	for m in markers:
		if out.size() >= LEAD_LIMIT:
			break
		# M7 polish: a lead on another level points at the door there; leads behind one door are one.
		var r := objective_route(m)
		var pos: Vector3 = r.position
		if pos.is_finite() and not (str(r.via_exit) != "" and taken.has(pos)):
			taken.append(pos)
			out.append({"marker_id": m, "position": pos, "via_exit": str(r.via_exit)})
	return out


## objectives() hook: marks the tracked quest's objective ("tracked": true, the others false).
func _p27_mark_tracked(objs: Array) -> void:
	var tracked := tracked_id()
	for o: Dictionary in objs:
		o["tracked"] = str(o.get("quest_id", "")) == tracked


## current_objective() hook: the tracked quest's objective, {} when it has none.
func _p27_tracked_objective() -> Dictionary:
	return tracked_objective()


## reset_for_tests() hook.
func _p27_reset() -> void:
	tracked_quest_id = ""

## @anchor P29
# --- the world's main thread and the near condition (P29; plan M6-M9 §2.12, §5.7) -------------------
# Two hook lines: _evaluate() calls _p29_follow_main() first, and condition_context() gives the near
# condition its target lookup (_p29_position_of).
#   * The main quest: quest.main (the Valley) until quest.world_main ("The Crown Unclaimed", started
#     by slice.completed) has started while quest.main is not active - after the crown, or after the
#     title's skip from world_start, where quest.main never ran. Then quest.world_main is the main
#     quest: listed and tracked first, its multi-marker `oaths` stage giving the compass its three oath
#     leads, its end the campaign's completion checkpoint. A test that points main_quest_id at a
#     fixture keeps it.
#   * near {target, radius_m}: the target's position is objective_position(target) - a live marker,
#     area or prop, else the level's world index (markers, areas, props, checkpoints, POIs, exits,
#     encounter centres).

const WORLD_MAIN_QUEST_ID := "quest.world_main"


## Makes quest.world_main the main quest once it has started while the Valley's is not active, and
## quest.main otherwise; a main quest a test chose is left alone.
func _p29_follow_main() -> void:
	if main_quest_id != MAIN_QUEST_ID and main_quest_id != WORLD_MAIN_QUEST_ID:
		return
	var world_state := quest_state(WORLD_MAIN_QUEST_ID) if _p29_has_world_main() else INACTIVE
	main_quest_id = p29_main_for(quest_state(MAIN_QUEST_ID), world_state)


## The main quest for the two main quests' states (pure): quest.world_main once it has started while
## quest.main is not active, else quest.main.
static func p29_main_for(valley_main_state: String, world_main_state: String) -> String:
	if world_main_state != INACTIVE and valley_main_state != ACTIVE:
		return WORLD_MAIN_QUEST_ID
	return MAIN_QUEST_ID


func _p29_has_world_main() -> bool:
	if scope.size() > 0 and not scope.has(WORLD_MAIN_QUEST_ID):
		return false
	return not quest_record(WORLD_MAIN_QUEST_ID).is_empty()


## The position of a near condition's target (QuestConditions.near): objective_position(id) - a live
## marker, area or prop, else the level's world index; Vector3.INF when nothing knows it.
func _p29_position_of(id: String) -> Vector3:
	return objective_position(id)


## @anchor P37
# --- world events as objectives (P37; plan M6-M9 §2.13, decision 27) ----------------------------------
# A running world event is shown like a quest - in the tracker (right after the main quest), the journal
# (active, with Track), the compass, the map and the HUD marker while it is tracked (the WanderDirector
# tracks it when it starts and gives the player's choice back when it ends) - so a new player sees what
# happens and where. The WanderDirector writes its objective here (p37_set_event: the shape of
# objective_for(), with the live position - a column's point moves - and the line "Defend Millford: 4 of
# 5 houses stand") and takes it away when it ends (p37_clear_event). Four hook lines: quest_state() (an
# event is ACTIVE while it runs), active_quest_ids() (_p37_insert_events), objective_for() (the event's
# objective) and reset_for_tests(). Nothing here is saved: a reload asks the WanderDirector again.

## event id -> its objective (objective_for()'s shape), while it runs.
var p37_events := {}


## A running world event's objective now (see the notes).
func p37_set_event(event_id: String, objective: Dictionary) -> void:
	p37_events[event_id] = objective.duplicate()


## The event ended (or its level was left): it is no objective any more.
func p37_clear_event(event_id: String) -> void:
	p37_events.erase(event_id)


## active_quest_ids() hook: `ids` with the running events right after the main quest (or first without one).
func _p37_insert_events(ids: PackedStringArray, main: bool) -> PackedStringArray:
	if p37_events.is_empty():
		return ids
	var keys := PackedStringArray(p37_events.keys())
	keys.sort()
	var out := PackedStringArray()
	if main:
		out.append(ids[0])
	out.append_array(keys)
	for i in range(1 if main else 0, ids.size()):
		out.append(ids[i])
	return out
