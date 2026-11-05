extends Node
## Quests (autoload "Quests"; plan §3.15, §4.5, §4.6; after GameSession in the autoload order):
## data-driven quests, the active dialogue session, the tutorial director and the slice's end.
##
## Active only in the Valley (GameSession.is_valley()) or while a test sets test_active; the
## sandbox has no quests and no tutorial (decision 28). Dialogue works anywhere.
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
	]


## True while quests and tutorials run: in the Valley, or when a test turned them on.
func is_active() -> bool:
	return test_active or GameSession.is_valley()


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
	if not is_active():
		return
	_sync_level()
	if _dirty or tick - _last_eval_tick >= EVALUATE_EVERY_TICKS:
		_evaluate(tick)
	tutorial.update(tick)


func _evaluate(tick: int) -> void:
	_dirty = false
	_last_eval_tick = tick
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
	var xp := int(srec.get("xp", 0))
	if xp > 0:
		Events.xp_award_requested.emit(xp, source)


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
	}


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
	return out


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
	return out


## The first objective of objectives() ({} when no quest is active).
func current_objective() -> Dictionary:
	for id in active_quest_ids():
		var o := objective_for(id)
		if not o.is_empty():
			return o
	return {}


## The objective of one active quest ({} when it is not active).
func objective_for(quest_id: String) -> Dictionary:
	var rec := quest_record(quest_id)
	if rec.is_empty() or quest_state(quest_id) != ACTIVE:
		return {}
	var sid := stage_of(quest_id)
	var srec := stage_record(rec, sid)
	if srec.is_empty():
		return {}
	var cond: Variant = srec.get("complete_when", {})
	var targets := QuestConditions.targets_of(cond)
	var marker := str(srec.get("marker", ""))
	var bot: Dictionary = (srec.get("bot", {}) as Dictionary).duplicate(true) if typeof(srec.get("bot")) == TYPE_DICTIONARY else {}
	return {"quest_id": quest_id, "stage_id": sid, "text": str(srec.get("objective", "")),
		"kind": str(cond.get("type", "")) if typeof(cond) == TYPE_DICTIONARY else "",
		"marker_id": marker, "position": objective_position(marker, targets), "targets": targets,
		"bot": bot, "title": str(rec.get("display_name", quest_id)), "main": quest_id == main_quest_id,
		"stage_index": _stage_index(rec, sid), "stage_count": _stages(rec).size()}


## Where an objective is: its marker, else the first of its targets found in the level (a living
## entity, an area trigger, a breakable prop). Vector3.INF when none is found.
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
	return Vector3.INF


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


func _tutorial_event(event_name: String, info: Dictionary, tick: int = -1) -> void:
	if not is_active():
		return
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
