class_name FactionState
extends RefCounted
## The standing of a faction toward the giant (plan §3.13 design 2, decision 17): Thornwick's
## guards and villagers ("village") are neutral until the giant offends them, turn hostile on a
## second offence within OFFENCE_WINDOW_S, or stand down when intimidated.
##
## The standing lives in WorldState flags, so checkpoints save it and reloads restore it:
##   faction.<f>.warned      set (overwritten) by every first offence
##   faction.<f>.hostile     try_set: a second offence within 30 s, or the cart barricade smashed
##                           (prop.cart_barricade's on_destroyed_flags; only the barricade sets
##                           quest.village.outcome = "force" - hostility never does)
##   faction.<f>.stood_down  try_set by the elder's intimidation choice (P15's dialogue data)
## Hostility wins over standing down (standing()).
##
## The static helpers read the flags. One shared hub (hub(), created by the first faction member
## that needs it, kept for the whole run) does the bookkeeping:
##   * Events.hit_resolved -> an offence: a direct (not area-effect) blow of a PLAYER-team
##     attacker that connected (HIT, BLOCKED, PARRIED, IMMUNE or GUARD_BROKEN) with a member of a
##     faction that is not hostile. One blow (attack instance) counts once, however many members it
##     hits. Area effects never reach faction members (HitFactory.skip_candidate, P03).
##   * Sim POST_RESOLVE, order 150: the offences of the tick in order. The first one, or one more
##     than 30 s after the previous, warns: set_flag(warned), faction_changed(..., "warned") and the
##     HUD line of TEXTS ("Thornwick's people cower. Strike again and they will fight you."). One within 30 s of the previous turns the faction hostile (try_set).
##     Offences older than 30 s are forgotten; without the warned flag (a new game, a test) there is
##     no previous offence.
##   * Events.flag_changed: faction.<f>.hostile / .stood_down becoming truthy (from any writer)
##     is announced in that POST_RESOLVE pass as faction_changed(tick, f, "hostile" | "stood_down"),
##     with a HUD line. Guards (EnemyActor, P11b) and civilians (Civilian) listen to it; actors
##     spawned later read the flags.

const HOOK_ORDER := 150
## A second offence within this many seconds of the previous one turns the faction hostile.
const OFFENCE_WINDOW_S := 30.0
## The outcomes of a blow that make it an offence: it connected (EVADED and IGNORED do not).
const OFFENCE_OUTCOMES := [HitResult.Outcome.HIT, HitResult.Outcome.BLOCKED, HitResult.Outcome.PARRIED,
	HitResult.Outcome.IMMUNE, HitResult.Outcome.GUARD_BROKEN]
## The flags of a faction's standing (faction.<f>.<state>) that are announced when they are set.
const ANNOUNCED := ["hostile", "stood_down"]
## The HUD line of each announced standing, per faction ("" = any other faction).
const TEXTS := {
	"village": {"warned": "Thornwick's people cower. Strike again and they will fight you.",
		"hostile": "Thornwick turns on you: its guards will fight.",
		"stood_down": "Thornwick's guards stand down."},
	"": {"warned": "They cower. Strike again and they will fight you.",
		"hostile": "They turn on you.", "stood_down": "They stand down."},
}
const KINDS := {"warned": "warn", "hostile": "bad", "stood_down": "info"}
## Offences kept in history (tests, debug).
const HISTORY_SIZE := 32
const NO_TICK := -1000000000

static var _hub: FactionState = null

## Offences handled so far, oldest first: {"tick", "faction", "target", "outcome", "action", "result"}
## (result: "warned" | "hostile").
var history: Array = []
var _last_offence: Dictionary = {}   # faction -> tick of its last offence
var _pending: Array = []             # offences of this tick, handled in POST_RESOLVE
var _announce: Array = []            # [faction, state] to announce in POST_RESOLVE
var _counted: Dictionary = {}        # attack instance id -> tick (one offence per blow)


# --------------------------------------------------------------------------- flags (static)

## "faction.<faction>.<state>", e.g. faction.village.hostile.
static func flag_id(faction: String, state: String) -> String:
	return "faction.%s.%s" % [faction, state]


static func flag_set(faction: String, state: String) -> bool:
	return faction != "" and truthy(WorldState.get_flag(flag_id(faction, state)))


static func is_hostile(faction: String) -> bool:
	return flag_set(faction, "hostile")


static func is_stood_down(faction: String) -> bool:
	return flag_set(faction, "stood_down")


static func is_warned(faction: String) -> bool:
	return flag_set(faction, "warned")


## What a member of `faction` acts on now: "hostile" (it wins over standing down), "stood_down",
## "warned" or "neutral". "" for no faction (always hostile, never a member).
static func standing(faction: String) -> String:
	if faction == "":
		return ""
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


## The faction a hit offends, or "" (see the class notes): a direct blow of a PLAYER-team attacker
## that connected with a living or protected member of a faction that is not hostile.
static func offended_faction(result: HitResult) -> String:
	if result == null or result.event == null or not OFFENCE_OUTCOMES.has(result.outcome):
		return ""
	var hit := result.event
	if hit.area_effect:
		return ""
	var attacker := Sim.get_entity(hit.attacker_id)
	if attacker == null or attacker.team != CombatEntity.Team.PLAYER:
		return ""
	var target := Sim.get_entity(hit.target_id)
	if target == null or target.faction == "" or is_hostile(target.faction):
		return ""
	return target.faction


## The outcome of an offence at `tick` after one at `last_tick` (NO_TICK = none): "hostile" when
## the faction was already warned and the previous offence lies at most `window_ticks` back,
## otherwise "warned" (pure: the rule the hub applies).
static func offence_result(warned: bool, last_tick: int, tick: int, window_ticks: int) -> String:
	if warned and last_tick != NO_TICK and tick - last_tick <= window_ticks:
		return "hostile"
	return "warned"


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
		_hub._last_offence.clear()
		_hub._pending.clear()
		_hub._announce.clear()
		_hub._counted.clear()


## The tick of `faction`'s last offence (NO_TICK = none).
func last_offence_tick(faction: String) -> int:
	return int(_last_offence.get(faction, NO_TICK))


## Moves `faction`'s last offence to `tick` (tests: "40 s ago" without simulating 40 s).
func set_last_offence_tick(faction: String, tick: int) -> void:
	_last_offence[faction] = tick


func _install() -> void:
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.flag_changed.connect(_on_flag_changed)
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
	var parts := id.split(".")
	if parts.size() != 3 or parts[0] != "faction" or not ANNOUNCED.has(parts[2]) or not truthy(value):
		return
	_announce.append([parts[1], parts[2]])


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


func _apply_offence(o: Dictionary) -> void:
	var faction := str(o.faction)
	if is_hostile(faction):
		return   # an earlier offence of this pass (or the barricade) already turned it
	var tick := int(o.tick)
	var result := offence_result(is_warned(faction), last_offence_tick(faction), tick,
		ActionDef.seconds_to_ticks(OFFENCE_WINDOW_S))
	_last_offence[faction] = tick
	var entry := o.duplicate()
	entry["result"] = result
	history.append(entry)
	while history.size() > HISTORY_SIZE:
		history.pop_front()
	if result == "hostile":
		WorldState.try_set_flag(flag_id(faction, "hostile"), true)   # announced through flag_changed
		return
	WorldState.set_flag(flag_id(faction, "warned"), true)
	_emit_standing(tick, faction, "warned")


func _emit_standing(tick: int, faction: String, state: String) -> void:
	Events.faction_changed.emit(tick, faction, state)
	var text := text_for(faction, state)
	if text != "":
		Events.hud_message.emit(text, str(KINDS.get(state, "info")))


## The HUD line announcing `state` for `faction` ("" when there is none).
static func text_for(faction: String, state: String) -> String:
	var texts: Dictionary = TEXTS.get(faction, TEXTS[""])
	return str(texts.get(state, ""))
