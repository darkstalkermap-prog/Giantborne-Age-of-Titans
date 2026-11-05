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
##   and event (an edge: a matching event makes the prompt pending for EVENT_PENDING_S, until it
##   can be shown). A prompt is a candidate while its trigger holds, every requires_flags flag is
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
## - tutorial_shown(tick, id) and tutorial_dismissed(tick, id, reason) are emitted; `changed`
##   fires on both. The HUD widget resolves {placeholders} (TutorialText).

signal changed

## How long an event trigger keeps a prompt pending while another prompt is showing.
const EVENT_PENDING_S := 6.0
const TICKS_PER_S := 60

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

var _pending: Dictionary = {}   ## prompt id -> tick its event trigger fired
var _armed: Dictionary = {}     ## once=false prompts: shown again only after their state trigger went false
var _cache: Array = []
var _cache_tick := -1


func setup(context: Callable, player: Callable) -> void:
	context_provider = context
	player_provider = player


## Forgets the prompt on screen and the pending ones without setting any flag (a new level, a
## reload, tests). A prompt that was showing will show again when its trigger holds.
func reset() -> void:
	current = {}
	_pending.clear()
	_armed.clear()
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


func update(tick: int) -> void:
	if not current.is_empty():
		_check_dismiss(tick)
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
## prompt's dismissal and makes event-triggered prompts pending.
func on_event(event_name: String, info: Dictionary, tick: int) -> void:
	if not current.is_empty():
		var d: Dictionary = current.dismiss
		var matched := false
		match str(d.get("type", "")):
			"event":
				matched = event_matches(d, event_name, info)
			"action_kind":
				matched = event_name == "ability_started" and str(info.get("actor", "")) == _player_id() \
					and str(info.get("action_kind", "")) == str(d.get("action_kind", ""))
			"action_id":
				matched = event_name == "ability_started" and str(info.get("actor", "")) == _player_id() \
					and str(info.get("action_id", "")) == str(d.get("action_id", ""))
		if matched:
			current.progress = int(current.progress) + 1
			if int(current.progress) >= int(current.needed):
				dismiss("done", tick)
	var ctx: Dictionary = {}
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


## Takes the shown prompt away: the seen flag, sets_flag when reason is "done",
## tutorial_dismissed.
func dismiss(reason: String, tick: int) -> void:
	if current.is_empty():
		return
	var id := str(current.id)
	var sets := str(current.get("sets_flag", ""))
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
