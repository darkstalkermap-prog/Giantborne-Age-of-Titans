class_name FactionState
extends RefCounted
## The standing of each faction toward the giant (plan M2-M5 §3.13 design 2, decision 17;
## generalised to faction records by P22, plan M6-M9 §2.12 and §3.4 design 6, decision 31).
##
## A faction is a record "faction.<short>" (data/world/faction_<short>.json; members carry the short
## name: an actor's `faction` "village" is faction.village, Thornwick): its texts, how many offences
## within how many seconds turn it hostile, its initial disposition and its manners toward a giant.
## A faction without a record (tests) keeps the M5 rules and the generic texts.
##
## The standing lives in WorldState flags under the record's flag_prefix (default the record id,
## so faction.village.<state>), so checkpoints save it and reloads restore it:
##   warned      set (overwritten) by every offence that does not turn the faction hostile
##   hostile     try_set: offences_to_hostile offences (default 2) within offence_window_s (30 s) of
##               each other, or another writer (the cart barricade's on_destroyed_flags; only the
##               barricade sets quest.village.outcome = "force" - hostility never does)
##   stood_down  try_set by an intimidation (the elder's dialogue, P15's data)
##   reconciled  set by reconcile(): the giant paid or did an errand (the faction record's
##               `reconcile` names the talker and the price; P29 ships the first one)
## standing(): reconciled wins over hostile, which wins over stood_down; a record whose `initial` is
## "hostile" (the toll-riders) is hostile from the start until it is reconciled. An offence against
## a reconciled faction is counted again: turning hostile clears `reconciled`.
##
## Offences (offended_faction): a direct (not area-effect) blow of a PLAYER-team attacker that
## connected (HIT, BLOCKED, PARRIED, IMMUNE or GUARD_BROKEN) with a member of a faction that is not
## hostile (area effects never reach members: HitFactory.skip_candidate); and, since P22, any damage
## the player deals - blows, abilities, trampling - to a prop that belongs to a faction and is tagged
## "house" or "engine" (prop_owner / prop_tags: the prop's `faction` / `prop_tags` property, its
## node meta of those names, or the prop record's prop_tags). One blow (attack instance) counts once,
## however many members or props it hits.
##
## One shared hub (hub(), created by the first faction member that needs it, kept for the whole run):
##   * Events.hit_resolved -> pending offences;
##   * Sim POST_RESOLVE, order 150: the offences of the tick in order: the hostile rule above, else a
##     warning (set_flag(warned), faction_changed(..., "warned") and the record's warn_text); then
##     the announcements: faction.<f>.hostile / .stood_down / .reconciled becoming truthy (from any
##     writer) is announced as faction_changed(tick, f, state) with the record's text. Guards
##     (EnemyActor, P11b) and civilians (Civilian) listen; actors spawned later read the flags;
##   * every STEP_BACK_CHECK_TICKS (P22, Thornwick): a member at peace (an EnemyActor with a faction
##     that is not hostile) with a living enemy (team ENEMY) within STEP_BACK_TRIGGER_M steps back
##     from it (EnemyActor.faction_step_back), so a fight beside the guards does not draw the giant's
##     blows onto them.
##
## P29 (plan M6-M9 §2.6, §2.12, §5.9; the W18 owner of this file):
##   * reconciliation by dialogue: a choice whose outcome is "reconcile_<short>" (the faction record's
##     `reconcile` talker offers it, paying its cost with take_items) calls reconcile(<short>) - every
##     time it is chosen, so a town that turned hostile again can be reconciled again (the choice's
##     set_flags would only write the flag once);
##   * the respawn blocker (respawn_refusal, which each level's EncounterDirector registers with
##     GameSession): a checkpoint is refused while a faction whose record has `respawn_guard_m` (P29's
##     field: Brannock and Millford, 120 m) is hostile and one of its armed members - a living spawn of
##     an enemy record in one of the level's encounters that is not cleared - stands within that
##     distance of it, so a death at Brannock never respawns the giant at the feet of the guards that
##     killed it (GameSession then picks the nearest visited checkpoint that is not refused).

const HOOK_ORDER := 150
const RECORD_PREFIX := "faction."
## M5 defaults (a faction without a record, or a record without the key).
const OFFENCE_WINDOW_S := 30.0
const OFFENCES_TO_HOSTILE := 2
## The outcomes of a blow that make it an offence: it connected (EVADED and IGNORED do not).
const OFFENCE_OUTCOMES := [HitResult.Outcome.HIT, HitResult.Outcome.BLOCKED, HitResult.Outcome.PARRIED,
	HitResult.Outcome.IMMUNE, HitResult.Outcome.GUARD_BROKEN]
## Prop tags whose damage offends the prop's faction.
const OFFENDED_PROP_TAGS := ["house", "engine"]
## The states announced when their flag becomes truthy.
const ANNOUNCED := ["hostile", "stood_down", "reconciled"]
## The record keys of each state's HUD line.
const TEXT_KEYS := {"warned": "warn_text", "hostile": "hostile_text", "stood_down": "stood_down_text",
	"reconciled": "reconciled_text"}
## The HUD lines of a faction without a record (or a record without the text).
const FALLBACK_TEXTS := {"warned": "They cower. Strike again and they will fight you.",
	"hostile": "They turn on you.", "stood_down": "They stand down.", "reconciled": "They forgive you."}
const KINDS := {"warned": "warn", "hostile": "bad", "stood_down": "info", "reconciled": "good"}
## Offences kept in history (tests, debug).
const HISTORY_SIZE := 32
const NO_TICK := -1000000000
## P22 (Thornwick): members at peace step back from an enemy this close (checked every
## STEP_BACK_CHECK_TICKS); they go back once none is within STEP_BACK_RELEASE_M.
const STEP_BACK_TRIGGER_M := 12.0
const STEP_BACK_RELEASE_M := 14.0
const STEP_BACK_CHECK_TICKS := 15
const MEMBER_GROUP := "enemies"

static var _hub: FactionState = null

## Offences handled so far, oldest first: {"tick", "faction", "target", "outcome", "action", "result"}
## (result: "warned" | "hostile").
var history: Array = []
## Step-backs started (tests, debug): [tick, member entity id, enemy entity id].
var step_backs: Array = []
var _offences: Dictionary = {}       # faction -> [ticks of its recent offences]
var _pending: Array = []             # offences of this tick, handled in POST_RESOLVE
var _announce: Array = []            # [faction, state] to announce in POST_RESOLVE
var _counted: Dictionary = {}        # attack instance id -> tick (one offence per blow)


# --------------------------------------------------------------------------- records (static)

## The faction record of a member's short name ("village" -> faction.village), or {}.
static func record_for(faction: String) -> Dictionary:
	if faction == "":
		return {}
	var rec: Dictionary = GameData.get_record(RECORD_PREFIX + faction)
	return rec if str(rec.get("type", "")) == "faction" else {}


## The short names of every faction record ("village", ...), sorted.
static func known_factions() -> PackedStringArray:
	var out := PackedStringArray()
	for rec: Dictionary in GameData.records_of_type("faction"):
		var id := str(rec.get("id", ""))
		if id.begins_with(RECORD_PREFIX):
			out.append(id.substr(RECORD_PREFIX.length()))
	out.sort()
	return out


## Direct offences within the window that turn the faction hostile (record, else 2).
static func offences_to_hostile(faction: String) -> int:
	return maxi(1, int(record_for(faction).get("offences_to_hostile", OFFENCES_TO_HOSTILE)))


## The window (s) within which offences count together (record, else 30).
static func offence_window_s(faction: String) -> float:
	return float(record_for(faction).get("offence_window_s", OFFENCE_WINDOW_S))


## "neutral" or "hostile": how the faction meets a giant before anything happened.
static func initial(faction: String) -> String:
	return str(record_for(faction).get("initial", "neutral"))


## How far (m, plus the giant's height) its civilians step out of a giant's way instead of fleeing;
## 0 when they flee (no record, civilians_give_way false: Thornwick).
static func give_way_m(faction: String) -> float:
	var rec := record_for(faction)
	if not bool(rec.get("civilians_give_way", false)):
		return 0.0
	return maxf(0.5, float(rec.get("give_way_m", 3.0)))


# --------------------------------------------------------------------------- flags (static)

## The flag of one of a faction's states: <flag_prefix>.<state> (faction.village.hostile).
static func flag_id(faction: String, state: String) -> String:
	var prefix := str(record_for(faction).get("flag_prefix", RECORD_PREFIX + faction))
	return "%s.%s" % [prefix, state]


static func flag_set(faction: String, state: String) -> bool:
	return faction != "" and truthy(WorldState.get_flag(flag_id(faction, state)))


static func is_reconciled(faction: String) -> bool:
	return flag_set(faction, "reconciled")


## Hostile now: its hostile flag, or a hostile initial disposition - unless reconciled.
static func is_hostile(faction: String) -> bool:
	if faction == "" or is_reconciled(faction):
		return false
	return flag_set(faction, "hostile") or initial(faction) == "hostile"


## Stood down (and not reconciled since).
static func is_stood_down(faction: String) -> bool:
	return flag_set(faction, "stood_down") and not is_reconciled(faction)


static func is_warned(faction: String) -> bool:
	return flag_set(faction, "warned")


## What a member of `faction` acts on now: "reconciled" (it wins over hostile), "hostile" (it wins
## over standing down), "stood_down", "warned" or "neutral". "" for no faction (always hostile,
## never a member). Members treat "reconciled" like "neutral": at peace, holding their posts.
static func standing(faction: String) -> String:
	if faction == "":
		return ""
	if is_reconciled(faction):
		return "reconciled"
	if is_hostile(faction):
		return "hostile"
	if is_stood_down(faction):
		return "stood_down"
	if is_warned(faction):
		return "warned"
	return "neutral"


static func truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v) != ""
	return true


# --------------------------------------------------------------------------- offences (static)

## The faction a hit offends, or "" (see the class notes): a member's faction for a direct blow that
## connected, a prop's faction for the player's damage to its house or engine.
static func offended_faction(result: HitResult) -> String:
	if result == null or result.event == null:
		return ""
	var hit := result.event
	var attacker := Sim.get_entity(hit.attacker_id)
	if attacker == null or attacker.team != CombatEntity.Team.PLAYER:
		return ""
	var target := Sim.get_entity(hit.target_id)
	if target == null:
		return ""
	if target.faction != "":
		if hit.area_effect or not OFFENCE_OUTCOMES.has(result.outcome) or is_hostile(target.faction):
			return ""
		return target.faction
	var owner := prop_owner(target)
	if owner == "" or is_hostile(owner) or result.health_damage <= 0:
		return ""
	for tag: String in prop_tags(target):
		if OFFENDED_PROP_TAGS.has(tag):
			return owner
	return ""


## The faction a prop belongs to: its actor's `faction` property (a string), else its node meta
## "faction"; "" for none. (A prop's CombatEntity keeps no faction, so the giant may still lock it
## and its area effects still reach it: TargetingRules.)
static func prop_owner(target: CombatEntity) -> String:
	if target == null or not is_instance_valid(target.actor):
		return ""
	var f: Variant = target.actor.get("faction")
	if typeof(f) == TYPE_STRING and f != "":
		return f
	return str(target.actor.get_meta(&"faction", ""))


## A prop's tags: its actor's `prop_tags` property, else its node meta "prop_tags", else its
## record's prop_tags.
static func prop_tags(target: CombatEntity) -> PackedStringArray:
	if target == null or not is_instance_valid(target.actor):
		return PackedStringArray()
	for v: Variant in [target.actor.get("prop_tags"), target.actor.get_meta(&"prop_tags", null),
			GameData.get_record(target.definition_id).get("prop_tags", null)]:
		if v is Array or v is PackedStringArray:
			return PackedStringArray(v)
	return PackedStringArray()


## The outcome of an offence at `tick` after one at `last_tick` (NO_TICK = none), M5's two-offence
## rule: "hostile" when the faction was already warned and the previous offence lies at most
## `window_ticks` back, otherwise "warned" (pure).
static func offence_result(warned: bool, last_tick: int, tick: int, window_ticks: int) -> String:
	return offence_result_n(warned, [] if last_tick == NO_TICK else [last_tick], tick, window_ticks, 2)


## The outcome of an offence at `tick` given the ticks of the earlier ones (`recent`, oldest first):
## "hostile" when the faction was already warned and this offence makes `needed` in a row, each at
## most `window_ticks` after the one before; otherwise "warned" (pure). needed 1: always hostile.
static func offence_result_n(warned: bool, recent: Array, tick: int, window_ticks: int, needed: int) -> String:
	if needed <= 1:
		return "hostile"
	if not warned:
		return "warned"
	var chain := 1
	var later := tick
	for i in range(recent.size() - 1, -1, -1):
		if later - int(recent[i]) > window_ticks:
			break
		chain += 1
		later = int(recent[i])
	return "hostile" if chain >= needed else "warned"


# --------------------------------------------------------------------------- the hub

## The shared hub, created (and connected to Events and Sim) on first use.
static func hub() -> FactionState:
	if _hub == null:
		_hub = FactionState.new()
		_hub._install()
	return _hub


## Forgets the offences in memory (tests). The flags are WorldState's (WorldState.clear()).
static func reset_for_tests() -> void:
	if _hub != null:
		_hub.history.clear()
		_hub.step_backs.clear()
		_hub._offences.clear()
		_hub._pending.clear()
		_hub._announce.clear()
		_hub._counted.clear()


## Reconciles the giant with `faction` (a reconcile dialogue choice, P29): sets
## <prefix>.reconciled, announced with the record's reconciled_text in the next POST_RESOLVE.
static func reconcile(faction: String) -> void:
	if faction == "":
		return
	hub()
	WorldState.set_flag(flag_id(faction, "reconciled"), true)


## The tick of `faction`'s last offence (NO_TICK = none).
func last_offence_tick(faction: String) -> int:
	var list: Array = _offences.get(faction, [])
	return int(list[-1]) if not list.is_empty() else NO_TICK


## Moves `faction`'s last offence to `tick` (tests: "40 s ago" without simulating 40 s).
func set_last_offence_tick(faction: String, tick: int) -> void:
	_offences[faction] = [tick]


func _install() -> void:
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.flag_changed.connect(_on_flag_changed)
	Events.dialogue_outcome.connect(_on_dialogue_outcome)   # P29: reconciliation
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_post_resolve, HOOK_ORDER)


func _on_hit_resolved(tick: int, result: HitResult) -> void:
	var faction := offended_faction(result)
	if faction == "":
		return
	var blow := result.event.instance_id
	if blow != 0 and _counted.has(blow):
		return
	_counted[blow] = tick
	_pending.append({"tick": tick, "faction": faction, "target": result.event.target_id,
		"outcome": result.outcome, "action": result.event.action_id})


func _on_flag_changed(_tick: int, id: String, value: Variant) -> void:
	if not truthy(value):
		return
	var dot := id.rfind(".")
	if dot <= 0:
		return
	var state := id.substr(dot + 1)
	if not ANNOUNCED.has(state):
		return
	var faction := faction_of_prefix(id.substr(0, dot))
	if faction != "":
		_announce.append([faction, state])


## The faction whose flags live under `prefix` ("faction.village" -> "village"): a record whose
## flag_prefix it is, else faction.<short>; "" otherwise.
static func faction_of_prefix(prefix: String) -> String:
	for rec: Dictionary in GameData.records_of_type("faction"):
		var id := str(rec.get("id", ""))
		if str(rec.get("flag_prefix", id)) == prefix and id.begins_with(RECORD_PREFIX):
			return id.substr(RECORD_PREFIX.length())
	var parts := prefix.split(".")
	if parts.size() == 2 and parts[0] == "faction" and parts[1] != "":
		return parts[1]
	return ""


func _on_post_resolve(tick: int) -> void:
	if not _pending.is_empty():
		var offences := _pending
		_pending = []
		for o: Dictionary in offences:
			_apply_offence(o)
	if not _announce.is_empty():
		var list := _announce
		_announce = []
		for a: Array in list:
			_emit_standing(tick, str(a[0]), str(a[1]))
	if not _counted.is_empty() and tick % 60 == 0:
		for blow: Variant in _counted.keys():
			if tick - int(_counted[blow]) > 60:
				_counted.erase(blow)
	if tick % STEP_BACK_CHECK_TICKS == 0:
		_check_step_backs(tick)


func _apply_offence(o: Dictionary) -> void:
	var faction := str(o.faction)
	if is_hostile(faction):
		return   # an earlier offence of this pass (or the barricade) already turned it
	var tick := int(o.tick)
	var window := ActionDef.seconds_to_ticks(offence_window_s(faction))
	var recent: Array = _offences.get(faction, [])
	var result := offence_result_n(is_warned(faction), recent, tick, window, offences_to_hostile(faction))
	recent.append(tick)
	while recent.size() > 16:
		recent.pop_front()
	_offences[faction] = recent
	var entry := o.duplicate()
	entry["result"] = result
	history.append(entry)
	while history.size() > HISTORY_SIZE:
		history.pop_front()
	if result == "hostile":
		var was_reconciled := is_reconciled(faction)
		if was_reconciled:
			WorldState.set_flag(flag_id(faction, "reconciled"), false)
		if not WorldState.try_set_flag(flag_id(faction, "hostile"), true) and was_reconciled:
			_announce.append([faction, "hostile"])   # the flag was already set: announce it here
		return   # otherwise announced through flag_changed
	WorldState.set_flag(flag_id(faction, "warned"), true)
	_emit_standing(tick, faction, "warned")


func _emit_standing(tick: int, faction: String, state: String) -> void:
	Events.faction_changed.emit(tick, faction, state)
	var text := text_for(faction, state)
	if text != "":
		Events.hud_message.emit(text, str(KINDS.get(state, "info")))


## The HUD line announcing `state` for `faction`: the record's text, else the generic one.
static func text_for(faction: String, state: String) -> String:
	var rec := record_for(faction)
	var key := str(TEXT_KEYS.get(state, ""))
	if key != "" and str(rec.get(key, "")) != "":
		return str(rec[key])
	return str(FALLBACK_TEXTS.get(state, ""))


# --------------------------------------------------------------------------- stepping back (P22)

## Every member at peace with a living enemy within STEP_BACK_TRIGGER_M steps back from the nearest
## one; a member whose nearest enemy is farther than STEP_BACK_RELEASE_M is told the fight moved off.
func _check_step_backs(tick: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var members: Array = []
	var enemies: Array = []
	for n in tree.get_nodes_in_group(MEMBER_GROUP):
		var a := n as EnemyActor
		if a == null or not a.is_inside_tree() or a.entity == null or a.entity.combatant == null \
				or not a.entity.is_alive():
			continue
		if a.member_at_peace():
			members.append(a)
		elif a.entity.team == CombatEntity.Team.ENEMY:
			enemies.append(a)
	if members.is_empty():
		return
	for m: EnemyActor in members:
		var nearest: EnemyActor = null
		var best := INF
		for e: EnemyActor in enemies:
			var d := Vector2(e.global_position.x - m.global_position.x,
				e.global_position.z - m.global_position.z).length()
			if d < best:
				best = d
				nearest = e
		if nearest != null and best <= STEP_BACK_TRIGGER_M:
			if m.step_back_point == Vector3.INF:
				step_backs.append([tick, m.entity_id, nearest.entity_id])
			m.faction_step_back(nearest.global_position)
		elif nearest == null or best > STEP_BACK_RELEASE_M:
			m.faction_step_back_clear()


# --------------------------------------------------------------------------- P29: reconcile, respawns

## A dialogue choice's outcome that reconciles a faction: "reconcile_<short>" (reconcile_brannock).
const RECONCILE_OUTCOME_PREFIX := "reconcile_"
## A respawn refused by a hostile faction's guards (its display name).
const RESPAWN_REFUSED_TEXT := "%s's guards hold the ground there."


## The faction a reconcile outcome names ("" for any other outcome, or an unknown faction).
static func reconcile_outcome_faction(outcome: String) -> String:
	if not outcome.begins_with(RECONCILE_OUTCOME_PREFIX):
		return ""
	var short := outcome.substr(RECONCILE_OUTCOME_PREFIX.length())
	return short if not record_for(short).is_empty() else ""


func _on_dialogue_outcome(_tick: int, _dialogue_id: String, outcome: String) -> void:
	var faction := reconcile_outcome_faction(outcome)
	if faction != "":
		reconcile(faction)


## How far (m) a hostile faction's armed members keep a respawn away (its record's respawn_guard_m;
## 0 = the faction does not block respawns).
static func respawn_guard_m(faction: String) -> float:
	return maxf(0.0, float(record_for(faction).get("respawn_guard_m", 0.0)))


## The respawn blocker (GameSession.register_respawn_blocker): why a respawn at `checkpoint_id` of the
## save's level is refused now ("" = fine) - see the class notes.
static func respawn_refusal(checkpoint_id: String) -> String:
	var level_id := GameSession.save_level_id()
	var idx := WorldIndex.for_level(level_id)
	if idx == null or not idx.has_checkpoint(checkpoint_id):
		return ""
	var at := idx.position_of(checkpoint_id)
	if not at.is_finite():
		return ""
	for faction in known_factions():
		var guard_m := respawn_guard_m(faction)
		if guard_m <= 0.0 or not is_hostile(faction):
			continue
		if not armed_members_near(level_id, faction, at, guard_m).is_empty():
			return RESPAWN_REFUSED_TEXT % str(record_for(faction).get("display_name", faction.capitalize()))
	return ""


## The entity ids of `faction`'s armed members on `level_id` that may stand within `radius_m` of
## `at` (horizontally, by their spawn points): spawns of enemy records in the level's encounters
## that are not cleared and that were not killed (pure data: the members need not be loaded).
static func armed_members_near(level_id: String, faction: String, at: Vector3, radius_m: float) -> PackedStringArray:
	var out := PackedStringArray()
	for enc: Dictionary in GameData.records_of_type("encounter"):
		if str(enc.get("level", "")) != level_id:
			continue
		if truthy(WorldState.get_flag(QuestConditions.encounter_flag(str(enc.get("id", ""))))):
			continue
		for sp: Variant in enc.get("spawns", []):
			if typeof(sp) != TYPE_DICTIONARY or str(sp.get("faction", "")) != faction:
				continue
			var def := GameData.get_record(str(sp.get("definition", "")))
			if str(def.get("type", "")) != "enemy" or WorldState.is_killed(str(sp.get("entity_id", ""))):
				continue
			var p: Variant = sp.get("position_m")
			if typeof(p) != TYPE_ARRAY or (p as Array).size() < 3:
				continue
			if Vector2(float(p[0]) - at.x, float(p[2]) - at.z).length() <= radius_m:
				out.append(str(sp.get("entity_id", "")))
	return out
