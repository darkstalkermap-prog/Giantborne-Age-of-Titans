class_name TutorialDirector
extends RefCounted
## The tutorial prompts (plan §3.15 design 5, §4.5): `tutorial_prompt` records shown one at a
## time while their trigger holds, until the player does what they teach. Owned and driven by the
## Quests autoload (Quests.tutorial): Quests calls update() every tick from its Sim POST_RESOLVE
## hook and on_event() for every TUTORIAL_EVENTS signal (with an `info` dictionary), both only
## while quests are active (the Valley, or a test).
##
## - Triggers: entered (the player is inside the area now: AreaTrigger.player_inside, a state, so
##   it combines with min_stage after growing inside the area), flag, level and stage (states),
##   and event (an edge: a matching event makes the prompt pending until it can be shown). M8 gate
##   (F28, F32): pending prompts queue - they do not age while another prompt holds the screen (two
##   prompts of one event, the world's arrival and the map, a shrine's ancestry and fast travel, show
##   one after the other; a shrine's lessons wait behind the map's), and lapse only after
##   EVENT_PENDING_S during which the screen was free but they were held back (in combat, the giant
##   dead). Before, a pending prompt lapsed 6 s after its event even while another showed, so the
##   map lesson (behind the arrival's 20 s) and the fast-travel lesson (behind the ancestry's) were
##   lost. A prompt is a candidate while its trigger holds, every requires_flags flag is
##   truthy, the player is at least min_stage and - for `once` prompts (the default) - its flag
##   tutorial.<name>.seen is not set. Event triggers record a prompt only when those already hold.
## - The candidate with the highest priority (then the lowest id) is shown when none is; a
##   defer_in_combat prompt waits while the player is in combat (hits exchanged recently,
##   ResourcePool.in_combat()). Nothing new shows while the player is dead.
## - Dismissal: action_kind / action_id (the player started `count` such actions), event
##   (`count` matching events), flag (the flag holds) or timeout (shown for timeout_s): reason
##   "done", which sets sets_flag. A timeout_s on the other kinds is a fallback: reason
##   "timeout", sets_flag untouched. Every dismissal sets the seen flag (a `once` prompt never
##   shows again). Counting starts when the prompt is shown. A prompt whose flag dismissal already
##   holds is not shown: it is marked seen and done at once.
## - Open lessons (M4 gate): a fallback takes the prompt away, not its lesson. While a prompt is
##   seen but its sets_flag is not set (a fallback dismissed it) and its dismissal is an action,
##   an event or a flag, the director keeps counting that dismissal without showing the prompt -
##   on from the prompt's progress when it went - and sets sets_flag once the player has done it
##   (no tutorial_shown / tutorial_dismissed). So what waits for the lesson's flag still follows
##   when the player does it later: quest.tutorial's awaken (two camera toggles) and spar
##   (tutorial.block.done, tutorial.dodge.done), tutorial.dodge's requires_flags, the dummies'
##   chain of flag triggers. The counts are level memory (reset() clears them, like hits_on); the
##   open lessons follow the saved flags.
## - tutorial_shown(tick, id) and tutorial_dismissed(tick, id, reason) are emitted; `changed`
##   fires on both. The HUD widget resolves {placeholders} (TutorialText).

signal changed

## How long an event trigger keeps a prompt pending while the screen is free but the prompt is held
## back (in combat, the giant dead); time behind another prompt does not count (M8 gate, F28, F32).
const EVENT_PENDING_S := 6.0
const TICKS_PER_S := 60
## Dismissal kinds that teach something the player does (a lesson that can stay open).
const LESSON_KINDS := ["action_kind", "action_id", "event", "flag"]

## The prompt on screen: {"id", "text", "priority", "shown_tick", "progress", "needed",
## "dismiss", "sets_flag", "once"}, or {} when none is shown.
var current: Dictionary = {}
## Every prompt shown since the last reset, in order (tests, debug).
var shown_ids: Array[String] = []
## () -> Dictionary: the QuestConditions context (Quests.condition_context).
var context_provider := Callable()
## () -> GiantPlayer (or null).
var player_provider := Callable()
## Tests and tools: when not empty, only these prompt ids are considered (fixtures stay apart from
## the shipped prompts).
var scope := PackedStringArray()

var _pending: Dictionary = {}   ## prompt id -> tick its event trigger fired, moved on by the time spent
                                ## behind a shown prompt (M8 gate: so its age counts the free screen only)
var _armed: Dictionary = {}     ## once=false prompts: shown again only after their state trigger went false
var _lesson_counts: Dictionary = {}   ## open lessons: prompt id -> matching actions or events so far
var _cache: Array = []
var _cache_tick := -1


func setup(context: Callable, player: Callable) -> void:
	context_provider = context
	player_provider = player


## Forgets the prompt on screen, the pending ones and the open lessons' counts without setting any
## flag (a new level, a reload, tests). A prompt that was showing will show again when its trigger
## holds; an open lesson stays open (its flags) and counts again from zero.
func reset() -> void:
	current = {}
	_pending.clear()
	_armed.clear()
	_lesson_counts.clear()
	_cache_tick = -1


## Re-reads the prompt records at the next use (a test that installed fixtures this tick).
func refresh_records() -> void:
	_cache_tick = -1


## The flag every dismissal sets: <prompt id>.seen (tutorial.block -> tutorial.block.seen).
static func seen_flag(prompt_id: String) -> String:
	return prompt_id + ".seen"


## Every tutorial_prompt record (only those in `scope` when it is set), sorted by id; re-read at
## most once per tick.
func prompts() -> Array:
	if _cache_tick != Sim.tick:
		_cache = []
		for rec: Dictionary in GameData.records_of_type("tutorial_prompt"):
			if scope.is_empty() or scope.has(str(rec.get("id", ""))):
				_cache.append(rec)
		_cache_tick = Sim.tick
	return _cache


func current_prompt() -> Dictionary:
	return current.duplicate(true)


## Ids of the prompts waiting for their turn (event triggers).
func pending_ids() -> PackedStringArray:
	var ids := PackedStringArray(_pending.keys())
	ids.sort()
	return ids


## True while a prompt's lesson is open: the prompt was seen but its sets_flag is not set (a
## fallback took it away), and its dismissal is something the player does (LESSON_KINDS).
static func lesson_open(rec: Dictionary, flags: Dictionary) -> bool:
	var sets := str(rec.get("sets_flag", ""))
	if sets == "" or QuestConditions.truthy(flags.get(sets)) \
			or not QuestConditions.truthy(flags.get(seen_flag(str(rec.get("id", ""))))):
		return false
	var d: Variant = rec.get("dismiss")
	return typeof(d) == TYPE_DICTIONARY and LESSON_KINDS.has(str((d as Dictionary).get("type", "")))


## Ids of the open lessons now (tests, debug).
func open_lesson_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var flags: Dictionary = _context().get("flags", {})
	for rec: Dictionary in prompts():
		if lesson_open(rec, flags):
			ids.append(str(rec.get("id", "")))
	return ids


## How many of an open lesson's actions or events were counted (0 when none or not open).
func lesson_count(prompt_id: String) -> int:
	return int(_lesson_counts.get(prompt_id, 0))


func update(tick: int) -> void:
	if not current.is_empty():
		_check_dismiss(tick)
	_check_flag_lessons()
	if not current.is_empty():
		return
	for id: Variant in _pending.keys():
		if tick - int(_pending[id]) > int(EVENT_PENDING_S * TICKS_PER_S):
			_pending.erase(id)
	var p: Variant = _player()
	if p != null and p.entity != null and not p.entity.is_alive():
		return
	var ctx := _context()
	var best: Dictionary = {}
	for rec: Dictionary in prompts():
		var id := str(rec.get("id", ""))
		var trig: Dictionary = rec.get("trigger", {}) if typeof(rec.get("trigger")) == TYPE_DICTIONARY else {}
		var fired := false
		if str(trig.get("type", "")) == "event":
			fired = _pending.has(id)
		else:
			var state := trigger_state(trig, ctx)
			if bool(rec.get("once", true)):
				fired = state
			else:
				if not state:
					_armed[id] = true
				fired = state and bool(_armed.get(id, true))
		if not fired or not eligible(rec, ctx):
			continue
		if bool(rec.get("defer_in_combat", false)) and _in_combat(p):
			continue
		if _dismissed_already(rec, ctx):
			_complete_silently(rec)
			continue
		if best.is_empty() or _ranks_higher(rec, best):
			best = rec
	if not best.is_empty():
		_show(best, tick)


## True when a prompt may be shown as far as its record goes: not yet seen (once prompts),
## every requires_flags flag truthy, the player at least min_stage.
func eligible(rec: Dictionary, ctx: Dictionary) -> bool:
	var flags: Dictionary = ctx.get("flags", {})
	if bool(rec.get("once", true)) and QuestConditions.truthy(flags.get(seen_flag(str(rec.get("id", ""))))):
		return false
	var req: Variant = rec.get("requires_flags", [])
	if typeof(req) == TYPE_ARRAY:
		for f: Variant in req:
			if not QuestConditions.truthy(flags.get(str(f))):
				return false
	return int(ctx.get("stage", 1)) >= int(rec.get("min_stage", 1))


## Whether a state trigger (entered, flag, level, stage) holds in `ctx`. "entered" is presence:
## the player is inside the area now.
static func trigger_state(trig: Dictionary, ctx: Dictionary) -> bool:
	match str(trig.get("type", "")):
		"entered":
			return (ctx.get("inside", {}) as Dictionary).has(str(trig.get("area", "")))
		"flag":
			return QuestConditions.flag_matches((ctx.get("flags", {}) as Dictionary).get(str(trig.get("flag", ""))), trig)
		"level":
			return int(ctx.get("level", 1)) >= int(trig.get("level", 1))
		"stage":
			return int(ctx.get("stage", 1)) >= int(trig.get("stage", 1))
	return false


## Whether an event (its `info`, built by Quests) matches a trigger or dismissal spec: the same
## event name and every filter of the spec (§2.8.3). Entity filters compare entity ids.
static func event_matches(spec: Dictionary, event_name: String, info: Dictionary) -> bool:
	if str(spec.get("event", "")) != event_name:
		return false
	for key: Variant in spec:
		var want: Variant = spec[key]
		match str(key):
			"type", "event", "count", "timeout_s":
				continue
			"target":
				if str(info.get("target", "")) != str(want):
					return false
			"action_tags_any":
				var tags: Array = info.get("tags", [])
				var any := false
				for t: Variant in want:
					if tags.has(str(t)):
						any = true
						break
				if not any:
					return false
			"actor_archetype":
				if str(info.get("archetype", "")) != str(want):
					return false
			"defender":
				if str(info.get("defender", "")) != str(want):
					return false
			"attacker":
				if str(info.get("attacker", "")) != str(want):
					return false
			"outcome_in":
				if not (want as Array).has(str(info.get("outcome", ""))):
					return false
			"near_player_m":
				if float(info.get("distance", INF)) > float(want):
					return false
			"grabbable":
				if bool(info.get("grabbable", false)) != bool(want):
					return false
			"actor":
				if str(info.get("actor", "")) != str(want):
					return false
			"action_kind":
				if str(info.get("action_kind", "")) != str(want):
					return false
			"action_id":
				if str(info.get("action_id", "")) != str(want):
					return false
			"non_empty":
				if (str(info.get("target", "")) != "") != bool(want):
					return false
			"phase":
				if int(info.get("phase", -1)) != int(want):
					return false
			"interact_prefix":
				if not str(info.get("interact_id", "")).begins_with(str(want)):
					return false
			_:
				return false
	return true


## A TUTORIAL_EVENTS event happened (info: see Quests' handlers). It counts toward the shown
## prompt's dismissal and the open lessons', and makes event-triggered prompts pending.
func on_event(event_name: String, info: Dictionary, tick: int) -> void:
	var shown_id := str(current.get("id", ""))
	if not current.is_empty() and dismiss_matches(current.dismiss, event_name, info):
		current.progress = int(current.progress) + 1
		if int(current.progress) >= int(current.needed):
			dismiss("done", tick)
	var ctx: Dictionary = {}
	for rec: Dictionary in prompts():
		var d: Variant = rec.get("dismiss")
		var lesson_id := str(rec.get("id", ""))
		if lesson_id == shown_id or typeof(d) != TYPE_DICTIONARY or not dismiss_matches(d, event_name, info):
			continue
		if ctx.is_empty():
			ctx = _context()
		if not lesson_open(rec, ctx.get("flags", {})):
			continue
		_lesson_counts[lesson_id] = int(_lesson_counts.get(lesson_id, 0)) + 1
		if int(_lesson_counts[lesson_id]) >= maxi(1, int((d as Dictionary).get("count", 1))):
			_learn_late(rec)
	for rec: Dictionary in prompts():
		var trig: Variant = rec.get("trigger")
		if typeof(trig) != TYPE_DICTIONARY or str(trig.get("type", "")) != "event" \
				or not event_matches(trig, event_name, info):
			continue
		var id := str(rec.get("id", ""))
		if not current.is_empty() and str(current.id) == id:
			continue
		if ctx.is_empty():
			ctx = _context()
		if eligible(rec, ctx):
			_pending[id] = tick


## Whether an event counts toward a dismissal: an `event` dismissal's matching event (its
## filters), or the player's own ability_started of an action_kind / action_id dismissal's kind or
## id. Timeouts and flags count no events.
func dismiss_matches(d: Dictionary, event_name: String, info: Dictionary) -> bool:
	match str(d.get("type", "")):
		"event":
			return event_matches(d, event_name, info)
		"action_kind":
			return event_name == "ability_started" and str(info.get("actor", "")) == _player_id() \
				and str(info.get("action_kind", "")) == str(d.get("action_kind", ""))
		"action_id":
			return event_name == "ability_started" and str(info.get("actor", "")) == _player_id() \
				and str(info.get("action_id", "")) == str(d.get("action_id", ""))
	return false


## Takes the shown prompt away: the seen flag, sets_flag when reason is "done",
## tutorial_dismissed. Any other reason (a fallback) leaves its lesson open, counted on from the
## prompt's progress. M8 gate (F28, F32): the prompts pending behind it get back the time it held the
## screen (their queue: see EVENT_PENDING_S).
func dismiss(reason: String, tick: int) -> void:
	if current.is_empty():
		return
	var id := str(current.id)
	var sets := str(current.get("sets_flag", ""))
	if reason != "done" and int(current.get("progress", 0)) > 0:
		_lesson_counts[id] = int(current.progress)
	_hold_pending(int(current.get("shown_tick", tick)), tick)
	current = {}
	WorldState.try_set_flag(seen_flag(id), true)
	if reason == "done" and sets != "":
		WorldState.try_set_flag(sets, true)
	Events.tutorial_dismissed.emit(tick, id, reason)
	changed.emit()


func _show(rec: Dictionary, tick: int) -> void:
	var id := str(rec.get("id", ""))
	var d: Dictionary = (rec.get("dismiss", {}) as Dictionary).duplicate(true) if typeof(rec.get("dismiss")) == TYPE_DICTIONARY else {}
	current = {"id": id, "text": str(rec.get("text", "")), "priority": int(rec.get("priority", 0)),
		"shown_tick": tick, "progress": 0, "needed": maxi(1, int(d.get("count", 1))), "dismiss": d,
		"sets_flag": str(rec.get("sets_flag", "")), "once": bool(rec.get("once", true))}
	_pending.erase(id)
	_armed[id] = false
	shown_ids.append(id)
	Events.tutorial_shown.emit(tick, id)
	changed.emit()


func _check_dismiss(tick: int) -> void:
	var d: Dictionary = current.dismiss
	var kind := str(d.get("type", ""))
	var elapsed := float(tick - int(current.shown_tick)) / TICKS_PER_S
	match kind:
		"timeout":
			if elapsed >= float(d.get("timeout_s", 0.0)) - 1e-6:
				dismiss("done", tick)
			return
		"flag":
			var flags: Dictionary = _context().get("flags", {})
			if QuestConditions.flag_matches(flags.get(str(d.get("flag", ""))), d):
				dismiss("done", tick)
				return
	if d.has("timeout_s") and elapsed >= float(d.timeout_s) - 1e-6:
		dismiss("timeout", tick)


## M8 gate (F28, F32): moves every pending prompt's tick on by the part of [shown_tick, tick] it spent
## pending behind the prompt on screen, so that time does not count against EVENT_PENDING_S.
func _hold_pending(shown_tick: int, tick: int) -> void:
	for id: Variant in _pending.keys():
		var since := int(_pending[id])
		_pending[id] = since + maxi(0, tick - maxi(since, shown_tick))


## A prompt whose flag dismissal already holds has nothing left to teach.
func _dismissed_already(rec: Dictionary, ctx: Dictionary) -> bool:
	var d: Variant = rec.get("dismiss")
	if typeof(d) != TYPE_DICTIONARY or str(d.get("type", "")) != "flag":
		return false
	return QuestConditions.flag_matches((ctx.get("flags", {}) as Dictionary).get(str(d.get("flag", ""))), d)


func _complete_silently(rec: Dictionary) -> void:
	var id := str(rec.get("id", ""))
	_pending.erase(id)
	_armed[id] = false
	WorldState.try_set_flag(seen_flag(id), true)
	var sets := str(rec.get("sets_flag", ""))
	if sets != "":
		WorldState.try_set_flag(sets, true)


## Open lessons taught by a flag: learnt once the flag holds (the shown prompt checks its own).
func _check_flag_lessons() -> void:
	var shown_id := str(current.get("id", ""))
	var flags: Dictionary = {}
	var have_flags := false
	for rec: Dictionary in prompts():
		var d: Variant = rec.get("dismiss")
		if typeof(d) != TYPE_DICTIONARY or str((d as Dictionary).get("type", "")) != "flag" \
				or str(rec.get("id", "")) == shown_id:
			continue
		if not have_flags:
			flags = _context().get("flags", {})
			have_flags = true
		if lesson_open(rec, flags) and QuestConditions.flag_matches(flags.get(str((d as Dictionary).get("flag", ""))), d):
			_learn_late(rec)


## An open lesson the player did after all: its sets_flag. The prompt stays seen and is not shown
## again; nothing is emitted but the flag's change (quests and flag triggers follow it).
func _learn_late(rec: Dictionary) -> void:
	var id := str(rec.get("id", ""))
	_lesson_counts.erase(id)
	WorldState.try_set_flag(str(rec.get("sets_flag", "")), true)


static func _ranks_higher(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa != pb:
		return pa > pb
	return str(a.get("id", "")) < str(b.get("id", ""))


func _context() -> Dictionary:
	if context_provider.is_valid():
		return context_provider.call()
	var ctx := QuestConditions.empty_context()
	ctx.flags = WorldState.flags
	return ctx


func _player() -> Variant:
	if player_provider.is_valid():
		var p: Variant = player_provider.call()
		if p != null and is_instance_valid(p):
			return p
	return null


func _player_id() -> String:
	var p: Variant = _player()
	if p != null and p.entity != null:
		return str(p.entity.entity_id)
	return "player"


static func _in_combat(p: Variant) -> bool:
	if p == null or p.entity == null or p.entity.combatant == null:
		return false
	return p.entity.combatant.pools.in_combat()
