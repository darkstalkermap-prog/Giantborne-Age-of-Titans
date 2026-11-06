class_name DialogueSession
extends RefCounted
## One running conversation with an NPC (plan §2.8.3, §3.15 design 3): a `dialogue` record's
## nodes and choices. Quests.start_dialogue() makes one and keeps it in Quests.dialogue; the
## dialogue screen (ui/screens/dialogue_screen.gd) shows it, and the Valley bot and tests call
## choose() on it directly without a screen.
##
## - begin(): the first entry whose conditions hold is the start node (false when none does);
##   emits dialogue_started.
## - choices(): the choices of the current node that may be taken now: their conditions hold
##   and their take_items are held. A node with no such choice offers one implicit "[Leave]".
## - choose(i) (i = an index into choices()) applies the choice's effects and moves to its
##   `next` node; next "" (or effects.close) ends the conversation:
##     set_flags      every flag with try_set_flag (first write wins)
##     outcome        the flag dialogue.<short id>.outcome.<outcome> (try_set_flag) and
##                    Events.dialogue_outcome
##     once_flag      the gate of the rewards: try_set_flag(once_flag); the rewards below are given
##                    only when it returns true, so a conversation repeated in a later session (or
##                    after a reload that kept the flag) grants nothing again (spec §14)
##     take_items     removed when the gate opens (every time when there is no once_flag)
##     give_items, xp, learn_abilities   the rewards (they require a once_flag): items into the
##                    inventory, Events.xp_award_requested(xp, "dialogue:<id>"), and each ability
##                    through the learner (the player's progression.learn_ability(id, "reward"))
##     attribute_points  (P20, a reward too) unspent attribute points added to the character
##                    through the attribute granter (Quests: the player's progression)
## - P20 (plan M6-M9 §2.12): a choice whose conditions fail (or whose take_items are not held)
##   but that has a `locked_text` is still listed, after the available ones, with "locked": true
##   and its reason ("Return when you stand at stage 5"); the screen shows it greyed and choose()
##   refuses it ("locked"). A node whose only choices are locked still offers [Leave] first.
## - end(reason) stops it once: dialogue_ended and the `ended` signal (Quests clears
##   Quests.dialogue on it).

signal ended(session: DialogueSession)

const LEAVE_TEXT := "[Leave]"

var dialogue_id := ""
var npc_id := ""
var record: Dictionary = {}
## The current node's id ("" before begin()).
var node_id := ""
var active := false
## Why it ended: "done" (a choice ended it), "left" (the implicit leave), or what end() was given.
var end_reason := ""
## The outcomes chosen in this conversation, in order.
var outcomes: Array[String] = []
## Every choice made: [{"node", "text", "outcome", "granted"}].
var history: Array = []
var last_result: Dictionary = {}
## () -> Dictionary: the QuestConditions context (Quests.condition_context); WorldState-only
## when not set.
var context_provider := Callable()
## (action_id: String, source: String) -> bool: teaches an ability; the player in group "player"
## (its progression component) when not set.
var learner := Callable()
## (points: int, source: String) -> void: adds unspent attribute points (P20); the player in group
## "player" (its progression component), else the session character, when not set.
var attribute_granter := Callable()


## Starts the conversation of `rec` with `p_npc_id`. False (and nothing emitted) when no entry
## holds or the record has no nodes.
func begin(rec: Dictionary, p_npc_id := "", p_context := Callable(), p_learner := Callable()) -> bool:
	record = rec
	dialogue_id = str(rec.get("id", ""))
	npc_id = p_npc_id
	context_provider = p_context
	learner = p_learner
	var start := start_node(rec, context())
	if start == "":
		return false
	node_id = start
	active = true
	Events.dialogue_started.emit(Sim.tick, dialogue_id, npc_id)
	return true


## The node the first entry whose conditions hold names ("" when none does).
static func start_node(rec: Dictionary, ctx: Dictionary) -> String:
	var entries: Variant = rec.get("entries")
	if typeof(entries) != TYPE_ARRAY:
		return ""
	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if QuestConditions.all_hold(e.get("conditions", []), ctx) and not node_record(rec, str(e.get("node", ""))).is_empty():
			return str(e.node)
	return ""


## The node record with this id ({} when there is none).
static func node_record(rec: Dictionary, id: String) -> Dictionary:
	var nodes: Variant = rec.get("nodes")
	if typeof(nodes) != TYPE_ARRAY or id == "":
		return {}
	for n: Variant in nodes:
		if typeof(n) == TYPE_DICTIONARY and str(n.get("id", "")) == id:
			return n
	return {}


func is_active() -> bool:
	return active


func speaker() -> String:
	return str(record.get("speaker", record.get("display_name", "")))


func node() -> Dictionary:
	return node_record(record, node_id)


func text() -> String:
	return str(node().get("text", ""))


## The condition context for this conversation now.
func context() -> Dictionary:
	if context_provider.is_valid():
		return context_provider.call()
	var ctx := QuestConditions.empty_context()
	ctx.flags = WorldState.flags
	ctx.deltas = WorldState.deltas
	ctx.inventory = WorldState.inventory
	return ctx


## The choices that may be taken now: [{"index", "source_index", "text", "next", "outcome",
## "implicit", "locked", "locked_text"}] ("index" is what choose() takes; "source_index" the
## choice's place in the node). A node without one offers a single implicit LEAVE_TEXT choice that
## ends the conversation. Locked choices (P20: failing conditions and a locked_text) follow, with
## "locked": true.
func choices() -> Array:
	var out: Array = []
	if not active:
		return out
	var ctx := context()
	var locked: Array = []
	var raw: Variant = node().get("choices", [])
	if typeof(raw) == TYPE_ARRAY:
		var j := 0
		for c: Variant in raw:
			if typeof(c) == TYPE_DICTIONARY:
				var effects: Dictionary = c.get("effects", {}) if typeof(c.get("effects")) == TYPE_DICTIONARY else {}
				var entry := {"index": 0, "source_index": j, "text": str(c.get("text", "")),
					"next": str(c.get("next", "")), "outcome": str(effects.get("outcome", "")), "implicit": false,
					"locked": false, "locked_text": ""}
				if _available(c, ctx):
					entry.index = out.size()
					out.append(entry)
				elif str(c.get("locked_text", "")) != "":
					entry.locked = true
					entry.locked_text = str(c.locked_text)
					locked.append(entry)
			j += 1
	if out.is_empty():
		out.append({"index": 0, "source_index": -1, "text": LEAVE_TEXT, "next": "", "outcome": "", "implicit": true,
			"locked": false, "locked_text": ""})
	for entry: Dictionary in locked:
		entry.index = out.size()
		out.append(entry)
	return out


static func _available(c: Dictionary, ctx: Dictionary) -> bool:
	if not QuestConditions.all_hold(c.get("conditions", []), ctx):
		return false
	var effects: Variant = c.get("effects")
	if typeof(effects) == TYPE_DICTIONARY and typeof(effects.get("take_items")) == TYPE_ARRAY:
		var inv: Dictionary = ctx.get("inventory", {})
		for t: Variant in effects.take_items:
			if typeof(t) == TYPE_DICTIONARY and int(inv.get(str(t.get("item", "")), 0)) < int(t.get("count", 1)):
				return false
	return true


## The index (into choices()) of the available choice whose outcome is `outcome`, or -1.
func find_choice(outcome: String) -> int:
	for c: Dictionary in choices():
		if str(c.outcome) == outcome and outcome != "" and not bool(c.get("locked", false)):
			return int(c.index)
	return -1


## Takes the choice with this outcome (the bot's village policies). {"ok": false, "reason":
## "no_such_choice"} when it is not offered now.
func choose_outcome(outcome: String) -> Dictionary:
	var i := find_choice(outcome)
	if i < 0:
		last_result = {"ok": false, "reason": "no_such_choice", "ended": not active}
		return last_result
	return choose(i)


## Takes choice `i` of choices(): applies its effects, then moves on or ends. Returns {"ok",
## "reason" ("" | "inactive" | "no_such_choice"), "ended", "node" (the node now, "" once ended),
## "outcome", "granted" (the rewards were given now)}.
func choose(i: int) -> Dictionary:
	if not active:
		last_result = {"ok": false, "reason": "inactive", "ended": true}
		return last_result
	var vis := choices()
	if i < 0 or i >= vis.size():
		last_result = {"ok": false, "reason": "no_such_choice", "ended": false}
		return last_result
	var c: Dictionary = vis[i]
	if bool(c.get("locked", false)):
		last_result = {"ok": false, "reason": "locked", "ended": false, "locked_text": str(c.locked_text)}
		return last_result
	if bool(c.implicit):
		history.append({"node": node_id, "text": str(c.text), "outcome": "", "granted": false})
		end("left")
		last_result = {"ok": true, "reason": "", "ended": true, "node": "", "outcome": "", "granted": false}
		return last_result
	var src: Dictionary = (node().get("choices", []) as Array)[int(c.source_index)]
	var effects: Dictionary = src.get("effects", {}) if typeof(src.get("effects")) == TYPE_DICTIONARY else {}
	var granted := _apply(effects)
	var outcome := str(effects.get("outcome", ""))
	history.append({"node": node_id, "text": str(c.text), "outcome": outcome, "granted": granted})
	var next := str(src.get("next", ""))
	if next == "" or bool(effects.get("close", false)) or node_record(record, next).is_empty():
		end("done")
	else:
		node_id = next
	last_result = {"ok": true, "reason": "", "ended": not active, "node": node_id if active else "",
		"outcome": outcome, "granted": granted}
	return last_result


## Applies a choice's effects. True when its rewards were given now (a once_flag set now).
func _apply(effects: Dictionary) -> bool:
	var source := "dialogue:%s" % dialogue_id
	var once := str(effects.get("once_flag", ""))
	var gate := once == "" or WorldState.try_set_flag(once, true)
	var set_flags: Variant = effects.get("set_flags")
	if typeof(set_flags) == TYPE_DICTIONARY:
		var keys: Array = (set_flags as Dictionary).keys()
		for f: Variant in keys:
			WorldState.try_set_flag(str(f), set_flags[f])
	var outcome := str(effects.get("outcome", ""))
	if outcome != "":
		WorldState.try_set_flag(QuestConditions.outcome_flag(dialogue_id, outcome), true)
		outcomes.append(outcome)
		Events.dialogue_outcome.emit(Sim.tick, dialogue_id, outcome)
	if not gate:
		return false
	for t: Variant in _list(effects.get("take_items")):
		if typeof(t) == TYPE_DICTIONARY:
			WorldState.remove_item(str(t.get("item", "")), int(t.get("count", 1)), source)
	if once == "":
		return false
	for g: Variant in _list(effects.get("give_items")):
		if typeof(g) == TYPE_DICTIONARY:
			WorldState.add_item(str(g.get("item", "")), int(g.get("count", 1)), source)
	var xp := int(effects.get("xp", 0))
	if xp > 0:
		Events.xp_award_requested.emit(xp, source)
	for id: Variant in _list(effects.get("learn_abilities")):
		_learn(str(id))
	var points := int(effects.get("attribute_points", 0))
	if points > 0:
		_grant_attribute_points(points, source)
	return true


## Adds unspent attribute points (P20): the attribute granter, else the player's progression,
## else the session character.
func _grant_attribute_points(points: int, source: String) -> void:
	if attribute_granter.is_valid():
		attribute_granter.call(points, source)
		return
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node = tree.get_first_node_in_group("player") if tree != null else null
	if p != null and "progression" in p and p.get("progression") != null:
		var prog: Object = p.get("progression")
		prog.set("unspent_attribute_points", int(prog.get("unspent_attribute_points")) + points)
	else:
		GameSession.character["unspent_attribute_points"] = int(GameSession.character.get("unspent_attribute_points", 0)) + points
	Events.attributes_changed.emit(Sim.tick)


func _learn(action_id: String) -> bool:
	if learner.is_valid():
		return bool(learner.call(action_id, "reward"))
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node = tree.get_first_node_in_group("player") if tree != null else null
	if p == null or not ("progression" in p) or p.get("progression") == null:
		push_warning("DialogueSession: no player progression to teach %s" % action_id)
		return false
	return bool(p.get("progression").learn_ability(action_id, "reward"))


static func _list(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


## Ends the conversation once (dialogue_ended, then `ended`).
func end(reason := "closed") -> void:
	if not active:
		return
	active = false
	end_reason = reason
	Events.dialogue_ended.emit(Sim.tick, dialogue_id)
	ended.emit(self)
