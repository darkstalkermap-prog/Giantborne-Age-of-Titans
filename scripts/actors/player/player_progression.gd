class_name PlayerProgression
extends PlayerComponent
## The giant's progression (spec §9, plan §3.14 design 2): XP and levels, attribute and talent
## points, the abilities a level (or a reward) teaches and where they are slotted, kill XP and
## enemy loot. The `progression` component of GiantPlayer.COMPONENTS; the rules themselves are
## Progression's (pure).
##
## - Level gating is on only after apply_state() applied a character level below 99: the Valley
##   (New Game, Continue, checkpoint reloads) and tests that apply a character. The sandbox giant
##   and fresh test giants keep controller.level = 99 (no gating); they still earn XP and levels
##   (shown, with points to spend at the sandbox shrine), but nothing is ever locked.
## - XP: Events.xp_award_requested (props, quests, dialogue), a kill by the player (below) and the
##   F8 debug key (+100). add_xp emits xp_gained(tick, amount, source, total); every level gained
##   adds 3 attribute points and 1 talent point, emits level_changed once, pushes the level into
##   the controller (when gated) and learns the abilities the new level meets.
## - Kills: Events.entity_died with the player as the killer (weapon blows, projectiles, throws
##   and crushes all carry the player's id) of a team ENEMY actor in the group "enemies": the
##   record's xp_reward, and its loot table - the actor's own `loot_table` (a per-spawn override
##   set by the director), else the record's - once per entity id (Loot.award_once). NEUTRAL
##   actors (village guards before the village turns hostile, dummies) and props give nothing
##   here (props award their own XP through xp_award_requested).
## - Abilities: newly met ones (unlock_level <= level, unlock_stage <= stage, in the progression
##   record's ability_library) are learned on a level-up or a growth, and learn_ability(id, source)
##   teaches one early (a quest or dialogue reward: then it is level_exempt). A learned ability is
##   known (GiantPlayer.known_abilities), in the controller's library, auto-slotted
##   (Progression.auto_slot: its §4.7 slot when free, else the first free slot, the ultimate slot
##   for an ultimate) and announced with ability_learned(tick, id, slot) (the HUD notice waits until
##   the player is out of combat).
## - Attributes: allocate(delta) spends points (Progression.allocate) and sets them on the
##   combatant (Combatant.set_attributes: the derived maxima keep their fractions; Dexterity's
##   recovery_scale reaches the controller), then emits attributes_changed.
## - Loadout: set_slot(slot, id, shrine) only at a shrine whose record allows it, outside combat.
## - Save state (CharacterState.PROGRESSION_KEYS): level (99 while ungated), xp (the total),
##   unspent_attribute_points, talent_points, attributes, level_exempt and ancestry. A restore is
##   silent. known_abilities and the loadout are GiantPlayer's core keys (it applies them after
##   the components); this component learns into the same list.
## - Stage evolutions (P31, plan M6-M9 §2.11, decision 23): an evolution (an ability with
##   evolves_from: Titan Stomp, Crag Hurl at stage 4, Formation Sweep, Titan Roar at 5, Earthquake at
##   6) is learned on reaching its unlock_stage at or above its unlock_level - through the library
##   like any ability, or through its growth profile's unlocks - and replaces its base: it goes into
##   the base's slot and the base's place in known_abilities, the base stays known (listed: the
##   shrine shows it evolved and no longer offers it for a slot), Events.ability_learned (the slot)
##   and Events.ability_evolved(tick, base, evolution, slot) are emitted. Cooldowns stay per id. A
##   gated giant's growth learns its stage's evolutions when the profile changes (on_profile_changed:
##   before PlayerGrowth's unlocks, which then find them known) and announces them with the growth
##   (growth_changed; a restore drops the announcements); an evolution another path taught (an
##   ungated debug growth's unlocks, a reward) takes its base's slot at the next growth or level.

const UNGATED_LEVEL := CharacterState.MAX_LEVEL
const DEBUG_XP := 100
const SLOT_REASONS := ["no_shrine", "combat", "unknown_slot", "not_known", "wrong_kind", "evolved"]
const ANCESTRY_NOTE := "no modifiers in the prototype"

var level := 1
## The total XP earned (the save's "xp").
var xp := 0
var unspent_attribute_points := 0
var talent_points := 0
var ancestry := CharacterState.DEFAULT_ANCESTRY
## True once a character level below 99 was applied: controller.level follows `level`.
var gated := false
## The result of the last add_xp / allocate / set_slot (screens and tests read it).
var last_result: Dictionary = {}
## Every ability this component taught, oldest first: [{"id", "slot", "source"}].
var learned: Array = []
## P31: evolutions learned when the profile changed, announced with the growth
## ([{"id", "base", "slot"}]); a restore or a profile swap without a growth drops them.
var _pending_evolutions: Array = []


func setup(p: GiantPlayer) -> void:
	super(p)
	ancestry = str(player.record.get("ancestry", CharacterState.DEFAULT_ANCESTRY))
	level = Progression.level_for_xp(xp)
	for pair: Array in _listeners():
		var sig: Signal = pair[0]
		if not sig.is_connected(pair[1]):
			sig.connect(pair[1])


func _listeners() -> Array:
	return [[Events.xp_award_requested, _on_xp_award_requested], [Events.entity_died, _on_entity_died],
		[Events.growth_changed, _on_growth_changed]]


func on_exit() -> void:
	for pair: Array in _listeners():
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


# --------------------------------------------------------------------------- queries

func is_gated() -> bool:
	return gated


## The six attributes as whole numbers (the combatant holds them).
func attributes() -> Dictionary:
	return Progression.attributes_of(player.entity.combatant.attributes)


## [XP earned inside the current level, XP the level needs] (needed 0 at the level cap).
func level_progress() -> Array:
	return Progression.level_progress(level, xp)


func xp_into_level() -> int:
	return int(level_progress()[0])


func xp_needed() -> int:
	return int(level_progress()[1])


func at_level_cap() -> bool:
	return level >= Progression.level_cap()


## The progression keys as a character dictionary (Progression's rules work on it).
func character_view() -> Dictionary:
	return {"level": level, "xp": xp, "unspent_attribute_points": unspent_attribute_points,
		"talent_points": talent_points, "attributes": attributes()}


func level_exempt_ids() -> Array:
	var out: Array = []
	for id: Variant in player.controller.level_exempt:
		out.append(str(id))
	return out


func ancestry_name() -> String:
	var rec := GameData.get_record(ancestry)
	return str(rec.get("display_name", ancestry))


## "Ancestry: Unaligned — no modifiers in the prototype" (decision 20).
func ancestry_line() -> String:
	return "Ancestry: %s — %s" % [ancestry_name(), ANCESTRY_NOTE]


func library() -> Array:
	return Progression.library()


func knows(id: String) -> bool:
	return player.known_abilities.has(id)


# --------------------------------------------------------------------------- XP and levels

## Adds XP (amount <= 0: nothing). Emits xp_gained; on a level-up level_changed, a HUD line, the
## level pushed to the controller (when gated) and the newly met abilities learned. Returns
## Progression.add_xp's result plus "learned" (ids) on a level-up.
func add_xp(amount: int, source: String) -> Dictionary:
	var c := character_view()
	var r := Progression.add_xp(c, amount)
	if int(r.gained) <= 0:
		return r
	xp = int(c.xp)
	level = int(c.get("level", level))
	unspent_attribute_points = int(c.get("unspent_attribute_points", unspent_attribute_points))
	talent_points = int(c.get("talent_points", talent_points))
	Events.xp_gained.emit(Sim.tick, int(r.gained), source, xp)
	if int(r.new_level) > int(r.old_level):
		_push_level()
		Events.level_changed.emit(Sim.tick, int(r.old_level), level)
		Events.hud_message.emit(level_up_text(r), "good")
		r["learned"] = _learn_met("level")
	last_result = r
	return r


## "Level 3! +3 attribute points, +1 talent point" for an add_xp result with a level-up.
static func level_up_text(r: Dictionary) -> String:
	var a := int(r.get("attribute_points", 0))
	var t := int(r.get("talent_points", 0))
	return "Level %d! +%d attribute point%s, +%d talent point%s" % [int(r.get("new_level", 1)),
		a, "" if a == 1 else "s", t, "" if t == 1 else "s"]


func _push_level() -> void:
	player.controller.level = level if gated else UNGATED_LEVEL


## True when a death of `e` rewards the player who killed it: a team ENEMY actor in "enemies".
static func is_reward_kill(e: CombatEntity) -> bool:
	return e != null and e.team == CombatEntity.Team.ENEMY and e.actor != null \
		and is_instance_valid(e.actor) and e.actor.is_in_group("enemies")


## The loot table a killed enemy drops: its actor's own loot_table, else its record's ("" = none).
static func loot_table_of(e: CombatEntity) -> String:
	if e == null:
		return ""
	if e.actor != null and is_instance_valid(e.actor) and "loot_table" in e.actor:
		var own := str(e.actor.get("loot_table"))
		if own != "":
			return own
	return str(e.combatant.base_record.get("loot_table", "")) if e.combatant != null else ""


func _on_xp_award_requested(amount: int, source: String) -> void:
	add_xp(amount, source)


func _on_entity_died(_tick: int, entity_id: String, killer_id: String) -> void:
	if player == null or not is_instance_valid(player) or killer_id != player.entity.entity_id \
			or entity_id == killer_id:
		return
	var e := Sim.get_entity(entity_id)
	if not is_reward_kill(e):
		return
	if e.combatant.xp_reward > 0:
		add_xp(e.combatant.xp_reward, "kill:%s" % entity_id)
	var table := loot_table_of(e)
	if table != "":
		Loot.award_once(entity_id, table, killer_id)


func _on_growth_changed(_tick: int, entity_id: String, old_stage: int, new_stage: int) -> void:
	if player != null and is_instance_valid(player) and entity_id == player.entity.entity_id \
			and new_stage > old_stage:
		_announce_pending("growth")
		_learn_met("growth")


# --------------------------------------------------------------------------- abilities

## Teaches `id` (an ability or ultimate) now: known, in the library, level_exempt when its
## unlock_level is above the character level, auto-slotted, ability_learned (and loadout_changed
## when slotted). False (nothing changes) when it is already known or not a learnable action.
## Dialogue and quest rewards call it with source "reward". P31: an evolution takes its base's slot
## and place in the known list and also emits ability_evolved (when the base was known).
func learn_ability(id: String, source: String) -> bool:
	var def := GameData.get_action(id)
	if def == null or not Progression.LEARNABLE_KINDS.has(def.kind) or knows(id):
		return false
	var r := _take(id, def)
	_announce(id, r, source)
	return true


## Learns every ability of the library the giant meets now and does not know - its evolutions first,
## chain link by chain link - then lets any evolution taught another way take its base's slot.
## Returns the ids learned.
func _learn_met(source: String) -> Array:
	var out: Array = []
	for id in Progression.evolutions_met(library(), player.known_abilities, level, player.growth_stage):
		if learn_ability(id, source):
			out.append(id)
	for id in Progression.newly_met(library(), player.known_abilities, level, player.growth_stage):
		if learn_ability(id, source):
			out.append(id)
	_evolve_known()
	return out


func _is_slotted(id: String) -> bool:
	return _slot_of(id) != ""


## The slot key holding `id` ("" = none).
func _slot_of(id: String) -> String:
	if id == "":
		return ""
	for key: String in GiantPlayer.SLOT_KEYS:
		if str(player.controller.loadout.get(key, "")) == id:
			return key
	return ""


# --------------------------------------------------------------------------- evolutions (P31)

## Makes `id` known and slotted, silently: an evolution of a known base takes the base's place in
## known_abilities (the base moves one on, still known) and the base's slot - once the giant's stage
## allows it; one learned earlier (a reward) is only known until then (_evolve_known moves it in).
## Anything else is appended and auto-slotted (Progression.auto_slot). Returns {"slot" (the key or
## ""), "base" (the known base it replaced, "" = none), "changed" (the loadout changed)}.
func _take(id: String, def: ActionDef) -> Dictionary:
	var base := Progression.base_of(id)
	var known := player.known_abilities
	var at := known.find(base) if base != "" else -1
	var waits := at >= 0 and def.unlock_stage > player.growth_stage
	if at >= 0 and not waits:
		known.insert(at, id)
	else:
		known.append(id)
	player.ensure_action(id)
	var c := player.controller
	if def.unlock_level > level:
		c.level_exempt[id] = true
	var slot := _slot_of(id)
	var changed := false
	var base_slot := _slot_of(base) if at >= 0 and not waits else ""
	if base_slot != "":
		if slot != "" and slot != base_slot:
			player.set_loadout_slot(slot, "")
		player.set_loadout_slot(base_slot, id)
		slot = base_slot
		changed = true
	elif slot == "" and not waits:
		slot = Progression.auto_slot(c.loadout, id, library())
		if slot != "":
			player.set_loadout_slot(slot, id)
			changed = true
	return {"slot": slot, "base": base if at >= 0 and not waits else "", "changed": changed}


## The events of an ability `_take` taught: loadout_changed (when slotted), ability_learned, and
## ability_evolved for an evolution of a known base.
func _announce(id: String, r: Dictionary, source: String) -> void:
	if bool(r.get("changed", false)):
		Events.loadout_changed.emit(Sim.tick, player.entity.entity_id)
	learned.append({"id": id, "slot": str(r.get("slot", "")), "source": source})
	Events.ability_learned.emit(Sim.tick, id, str(r.get("slot", "")))
	if str(r.get("base", "")) != "":
		Events.ability_evolved.emit(Sim.tick, str(r.base), id, str(r.get("slot", "")))


func _announce_pending(source: String) -> void:
	var pending := _pending_evolutions
	_pending_evolutions = []
	for p: Dictionary in pending:
		if knows(str(p.id)):
			_announce(str(p.id), p, source)


## An evolution the giant knows and may use (its stage reached, its level reached or exempt or
## gating off) whose base still holds a slot - taught by a growth profile's unlocks (PlayerGrowth
## puts those into the first empty slot) or a reward - moves into its base's slot (and out of any
## other), takes the base's place in known_abilities and is announced with ability_evolved. Returns
## the ids moved.
func _evolve_known() -> Array:
	var out: Array = []
	for id: String in player.known_abilities.duplicate():
		var base := Progression.base_of(id)
		var base_slot := _slot_of(base)
		var def := GameData.get_action(id)
		if base_slot == "" or def == null or def.unlock_stage > player.growth_stage:
			continue
		if gated and def.unlock_level > level and not player.controller.level_exempt.has(id):
			continue
		var slot := _slot_of(id)
		if slot != "":
			player.set_loadout_slot(slot, "")
		player.set_loadout_slot(base_slot, id)
		var known := player.known_abilities
		known.erase(id)
		known.insert(maxi(0, known.find(base)), id)
		Events.loadout_changed.emit(Sim.tick, player.entity.entity_id)
		Events.ability_evolved.emit(Sim.tick, base, id, base_slot)
		out.append(id)
	return out


## The known ability `id` has evolved into ("" = none): a known evolution of it that the giant's stage
## allows (one taught early waits for its stage). The base stays known and listed; its slot is the
## evolution's.
func evolved_into(id: String) -> String:
	for ev in Progression.evolutions_known(id, player.known_abilities):
		var def := GameData.get_action(ev)
		if def != null and def.unlock_stage <= player.growth_stage:
			return ev
	return ""


## A growth of a gated giant learns the stage's evolutions as the profile changes - before
## PlayerGrowth applies the profile's unlocks, which then find them known and leave their slots
## alone - and keeps their announcements for growth_changed. Profile swaps that shrink, or of an
## ungated giant (the sandbox, tests that set a profile), learn nothing here.
func on_profile_changed(old_profile: Dictionary, new_profile: Dictionary) -> void:
	var new_stage := int(new_profile.get("stage", 1))
	if not gated or new_stage <= int(old_profile.get("stage", 1)):
		return
	var unlocks: Variant = new_profile.get("unlocks", [])
	var extra: Array = unlocks if typeof(unlocks) == TYPE_ARRAY else []
	for id in Progression.evolutions_met(library(), player.known_abilities, level, new_stage, extra):
		var def := GameData.get_action(id)
		if def != null and not knows(id):
			_pending_evolutions.append(_take(id, def).merged({"id": id}))


## A profile swap without a growth (a test, a restore) drops the announcements it queued.
func post_movement(_tick: int, _dt: float) -> void:
	if not _pending_evolutions.is_empty():
		_pending_evolutions.clear()


# --------------------------------------------------------------------------- attributes

## Spends attribute points ({attribute: points}); see Progression.allocate for the refusals. On
## success the combatant gets the new attributes and attributes_changed is emitted.
func allocate(delta: Dictionary) -> Dictionary:
	var c := character_view()
	var r := Progression.allocate(c, delta)
	if r.ok:
		unspent_attribute_points = int(c.unspent_attribute_points)
		player.entity.combatant.set_attributes(c.attributes)
		var parts := PackedStringArray()
		for key: String in Progression.ATTRIBUTE_KEYS:
			if int(delta.get(key, 0)) > 0:
				parts.append("%s +%d" % [Progression.attribute_name(key), int(delta[key])])
		r["message"] = "Raised %s." % ", ".join(parts)
		Events.attributes_changed.emit(Sim.tick)
	last_result = r
	return r


## The derived values after adding `delta` ({attribute: points}) to the current attributes, with
## the current growth bonus (Progression.derived_preview).
func derived_preview(delta: Dictionary = {}) -> Dictionary:
	var attrs := attributes()
	for key: Variant in delta:
		if attrs.has(str(key)) and SchemaUtil.is_number(delta[key]):
			attrs[str(key)] = int(attrs[str(key)]) + int(delta[key])
	return Progression.derived_preview(player.record, attrs, player.entity.combatant.growth_bonus)


# --------------------------------------------------------------------------- loadout

## {ok, reason, message}: the loadout can be changed at `shrine` now (a shrine whose record has
## loadout true, outside combat).
func can_change_loadout(shrine: Node) -> Dictionary:
	var rec := PlayerGrowth.shrine_record(shrine)
	if rec.is_empty():
		return _fail("no_shrine", "Change your abilities at a shrine.")
	if not bool(rec.get("loadout", true)):
		return _fail("no_shrine", "This shrine cannot change your abilities.")
	if player.entity.combatant.pools.in_combat():
		return _fail("combat", "Not during combat.")
	return {"ok": true, "reason": "", "message": ""}


## The ids that may go into `slot_key`: "" (empty) first, then the known abilities of the right
## kind (ultimates only in "ultimate"), in library order, then any others known. P31: an ability
## that has evolved (Heavy Footfall once Titan Stomp is known) is no longer offered.
func slot_options(slot_key: String) -> PackedStringArray:
	var out := PackedStringArray([""])
	var ordered: Array = library()
	for id in player.known_abilities:
		if not ordered.has(id):
			ordered.append(id)
	for id_v: Variant in ordered:
		var id := str(id_v)
		if not knows(id) or out.has(id) or evolved_into(id) != "":
			continue
		var def := GameData.get_action(id)
		if def == null or not Progression.LEARNABLE_KINDS.has(def.kind):
			continue
		if (def.kind == "ultimate") == (slot_key == "ultimate"):
			out.append(id)
	return out


## Puts a known ability ("" = empty) into slot_1..slot_8 or "ultimate", at `shrine`, outside
## combat. An ability already in another slot swaps places with this slot's. Emits
## loadout_changed. {ok, reason (SLOT_REASONS), message}.
func set_slot(slot_key: String, action_id: String, shrine: Node) -> Dictionary:
	var check := can_change_loadout(shrine)
	if not check.ok:
		last_result = check
		return check
	if not slot_key in GiantPlayer.SLOT_KEYS:
		last_result = _fail("unknown_slot", "There is no slot '%s'." % slot_key)
		return last_result
	if action_id != "":
		var def := GameData.get_action(action_id)
		if def == null or not knows(action_id):
			last_result = _fail("not_known", "You have not learned that ability.")
			return last_result
		if (def.kind == "ultimate") != (slot_key == "ultimate"):
			last_result = _fail("wrong_kind", "Only an ultimate goes into the ultimate slot." if slot_key == "ultimate"
				else "An ultimate goes into the ultimate slot.")
			return last_result
		var evolved := evolved_into(action_id)
		if evolved != "":
			var ev_def := GameData.get_action(evolved)
			last_result = _fail("evolved", "%s has evolved into %s." % [def.display_name,
				ev_def.display_name if ev_def != null else evolved])
			return last_result
	var loadout := player.controller.loadout
	var previous := str(loadout.get(slot_key, ""))
	if action_id != "" and previous != action_id:
		for key: String in GiantPlayer.SLOT_KEYS:
			if key != slot_key and str(loadout.get(key, "")) == action_id:
				player.set_loadout_slot(key, previous)
	player.set_loadout_slot(slot_key, action_id)
	Events.loadout_changed.emit(Sim.tick, player.entity.entity_id)
	last_result = {"ok": true, "reason": "", "message": ""}
	return last_result


static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message}


# --------------------------------------------------------------------------- component hooks

## F8 (debug builds only: the router emits debug_xp only there): +100 XP.
func handle_edge(edge: StringName) -> bool:
	if edge != &"debug_xp":
		return false
	add_xp(DEBUG_XP, "debug")
	Events.hud_message.emit("DEBUG: +%d XP" % DEBUG_XP, "info")
	print("[progression] DEBUG: +%d XP -> level %d, %d XP" % [DEBUG_XP, level, xp])
	return true


## Applies the progression keys of a character (silently: no events, no notices). A level of 99
## turns gating off (the level shown then follows the XP); any other level turns it on.
func apply_state(state: Dictionary) -> void:
	_pending_evolutions.clear()   # P31: a restore announces nothing (its loadout follows the save)
	var anc: Variant = state.get("ancestry")
	if typeof(anc) == TYPE_STRING and str(GameData.get_record(str(anc)).get("type", "")) == "ancestry":
		ancestry = str(anc)
	if SchemaUtil.is_number(state.get("xp")):
		xp = maxi(0, int(state.xp))
	if SchemaUtil.is_number(state.get("unspent_attribute_points")):
		unspent_attribute_points = maxi(0, int(state.unspent_attribute_points))
	if SchemaUtil.is_number(state.get("talent_points")):
		talent_points = maxi(0, int(state.talent_points))
	if typeof(state.get("attributes")) == TYPE_DICTIONARY:
		player.entity.combatant.set_attributes(Progression.attributes_of(state.attributes, attributes()))
	if typeof(state.get("level_exempt")) == TYPE_ARRAY:
		var exempt := {}
		for id: Variant in state.level_exempt:
			if str(id) != "":
				exempt[str(id)] = true
		player.controller.level_exempt = exempt
	if SchemaUtil.is_number(state.get("level")):
		gated = not CharacterState.is_ungated(state)
		level = clampi(int(state.level), 1, Progression.level_cap()) if gated else Progression.level_for_xp(xp)
		_push_level()
	elif not gated:
		level = Progression.level_for_xp(xp)


func capture_state(out: Dictionary) -> void:
	out["level"] = level if gated else UNGATED_LEVEL
	out["xp"] = xp
	out["unspent_attribute_points"] = unspent_attribute_points
	out["talent_points"] = talent_points
	out["attributes"] = attributes()
	out["level_exempt"] = level_exempt_ids()
	out["ancestry"] = ancestry


func debug_info(out: Dictionary) -> void:
	var prog := level_progress()
	out["progression"] = "Lv %d%s  %d XP (%d / %d)  points %d  talents %d" % [level,
		"" if gated else " (ungated)", xp, int(prog[0]), int(prog[1]), unspent_attribute_points, talent_points]
