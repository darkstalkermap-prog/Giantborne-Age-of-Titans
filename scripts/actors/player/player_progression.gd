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
## - Talents and the ancestry (P33, plan M6-M9 §2.11, §5.12, decision 22; the rules are Talents'):
##   learn_talent(id) spends the talent's points once (out of combat; its tier's level reached -
##   any level while ungated - and the talent above it learned), learns the abilities it grants
##   (granted_by "talent", auto-slotted like any learned ability) and emits talent_learned.
##   choose_ancestry(id) - once, out of combat, once the Old Kingdom has opened (world_opened) - adds
##   the ancestry's attribute points, teaches its signature, sets the flag ancestry.chosen and emits
##   ancestry_chosen. Both are permanent and saved ("talents", "ancestry", "ancestry_chosen").
##   rebuild_passives() folds the talents' and the ancestry's modifiers into the combatant
##   (Combatant.set_passives: never statuses) on every change, on load and on growth, and applies the
##   two a combatant cannot apply alone: the stamina and essence costs and cooldowns of the actions
##   in the giant's controller library (per-character copies of the actions those passives change,
##   so the controller, the hotbar and refunds all see the same numbers), and the grab reach of the
##   giant's profile (a copy of the growth record with grab_reach_m raised while a passive adds
##   reach). The combatant's action_source is the giant's controller, so heavy, throw and magic
##   damage passives reach the action being performed.

const UNGATED_LEVEL := CharacterState.MAX_LEVEL
const DEBUG_XP := 100
const SLOT_REASONS := ["no_shrine", "combat", "unknown_slot", "not_known", "wrong_kind", "evolved"]
## P33: why choose_ancestry refuses (learn_talent: Talents.LEARN_REASONS and "combat").
const ANCESTRY_REASONS := ["unknown", "chosen", "not_yet", "combat"]

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
## P33: the learned talent ids, in learning order (the save's "talents").
var talents: Array = []
## P33: true once the ancestry was chosen (the save's "ancestry_chosen"): exactly when the ancestry is
## not the neutral (prologue) one.
var ancestry_chosen := false
## P33: the stamina cost, essence cost and cooldown multipliers the library's action copies carry,
## and the library's size when they were made (an action added since joins with its record's costs
## until the next sync, at the end of the tick).
var _cost_mults := Vector3.ONE
var _cost_lib_size := -1
## P33: the growth record the giant's profile copies (the profile itself while no passive changes
## it), and the grab reach the copy adds.
var _profile_base: Dictionary = {}
var _profile_copy: Dictionary = {}
var _profile_reach_add := 0.0


func setup(p: GiantPlayer) -> void:
	super(p)
	ancestry = str(player.record.get("ancestry", CharacterState.DEFAULT_ANCESTRY))
	level = Progression.level_for_xp(xp)
	_profile_base = player.profile
	player.entity.combatant.action_source = weakref(player.controller)
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


## The ancestry and what it gives, for the attribute screens (P33): "Ancestry: Stoneblood —
## Constitution +3, Endurance +2; Armour +10, Poise (staggers less) +20; Bedrock Ward", or before the
## choice "Ancestry: Unaligned — choose yours at a shrine of the Old Kingdom" (once the world has
## opened) / "... — your blood awakens when you reach the Old Kingdom".
func ancestry_line() -> String:
	if not ancestry_chosen or not Talents.is_choosable(ancestry):
		return "Ancestry: %s — %s" % [ancestry_name(), "choose yours at a shrine of the Old Kingdom"
			if world_opened() else "your blood awakens when you reach the Old Kingdom"]
	var s := Talents.ancestry_summary(ancestry)
	var parts := PackedStringArray()
	if str(s.attributes) != "":
		parts.append(str(s.attributes))
	if not (s.passives as PackedStringArray).is_empty():
		parts.append(", ".join(s.passives))
	var sig := GameData.get_action(str(s.signature_id))
	if sig != null:
		parts.append(sig.display_name)
	return "Ancestry: %s — %s" % [ancestry_name(), "; ".join(parts)]


## The talent points and talents, for the inventory and the attribute screens (P33): "Talent
## points: 2 — talents: Heavy Hands, Stone Hide" or "Talent points: 5 — learn talents at a shrine
## (the Talents tab)".
func talent_line() -> String:
	if talents.is_empty():
		return "Talent points: %d — learn talents at a shrine (the Talents tab)" % talent_points
	var names := PackedStringArray()
	for id: Variant in talents:
		names.append(Talents.display_name(str(id)))
	return "Talent points: %d — talents: %s" % [talent_points, ", ".join(names)]


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
## P33: every profile change (a growth, a restore) rebuilds the passives on the new profile (its
## grab reach copy) - this component is the last, so the others have read the record already.
func on_profile_changed(old_profile: Dictionary, new_profile: Dictionary) -> void:
	if not is_same(new_profile, _profile_copy):   # the copy set again keeps its record
		_profile_base = new_profile
	rebuild_passives()
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
## P33: then the library's action costs follow the passives (an action added this tick, a status
## that changed a cost multiplier) and so does the profile's grab reach.
func post_movement(_tick: int, _dt: float) -> void:
	if not _pending_evolutions.is_empty():
		_pending_evolutions.clear()
	_sync_action_costs()
	if player.entity.combatant.grab_reach_add() != _profile_reach_add:
		_sync_profile_passives()


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
## the current growth bonus and (P33) passives (Progression.derived_preview).
func derived_preview(delta: Dictionary = {}) -> Dictionary:
	var attrs := attributes()
	for key: Variant in delta:
		if attrs.has(str(key)) and SchemaUtil.is_number(delta[key]):
			attrs[str(key)] = int(attrs[str(key)]) + int(delta[key])
	var c := player.entity.combatant
	return Progression.derived_preview(player.record, attrs, c.growth_bonus, c.passives)


# --------------------------------------------------------------------------- talents and ancestry (P33)

## True once the Old Kingdom has opened to this character (the flag progress.world_entered, or the
## world being the level played): ancestries are offered from then on.
static func world_opened() -> bool:
	if QuestConditions.truthy(WorldState.get_flag(Talents.WORLD_FLAG)):
		return true
	return GameSession.current_level_id() == GameSession.WORLD_LEVEL_ID


## True while the shrines offer the ancestry: not chosen yet, and the world has opened.
func ancestry_offered() -> bool:
	return not ancestry_chosen and world_opened()


## The character the talent rules read ({"level", "talent_points", "talents"}); an ungated giant
## (the sandbox) counts as level 99, so no tier is closed to it.
func talent_view() -> Dictionary:
	return {"level": level if gated else UNGATED_LEVEL, "talent_points": talent_points, "talents": talents.duplicate()}


func knows_talent(id: String) -> bool:
	return talents.has(id)


## {ok, reason, message}: talent `id` can be learned now - out of combat (reason "combat"), then
## Talents.check (unknown, known, level, requires, points).
func can_learn_talent(id: String) -> Dictionary:
	if player.entity.combatant.pools.in_combat():
		return _fail("combat", "Not during combat.")
	return Talents.check(talent_view(), id)


## Learns talent `id` (can_learn_talent first): its points are spent once, its granted abilities
## are learned (source "talent": auto-slotted, ability_learned), a replacement takes its old
## ability's slot, the passives are rebuilt, talent_learned and a HUD line are emitted.
## {ok, reason, message, spent, learned (ability ids)}.
func learn_talent(id: String) -> Dictionary:
	var check := can_learn_talent(id)
	if not check.ok:
		check["spent"] = 0
		check["learned"] = []
		last_result = check
		return check
	var c := talent_view()
	var r := Talents.learn(c, id)
	talent_points = int(c.talent_points)
	talents = c.talents
	var taught: Array = []
	for g: Variant in Talents.grants_of(id):
		if learn_ability(str(g), "talent"):
			taught.append(str(g))
	var replaces := Talents.replaces_of(id)
	for old: Variant in replaces:
		var new_id := str(replaces[old])
		if learn_ability(new_id, "talent"):
			taught.append(new_id)
		var slot := _slot_of(str(old))
		if slot != "" and knows(new_id):
			var previous := _slot_of(new_id)
			if previous != "" and previous != slot:
				player.set_loadout_slot(previous, "")
			player.set_loadout_slot(slot, new_id)
			Events.loadout_changed.emit(Sim.tick, player.entity.entity_id)
	rebuild_passives()
	Events.talent_learned.emit(Sim.tick, id)
	var line := "Talent learned: %s" % Talents.display_name(id)
	if not taught.is_empty():
		var names := PackedStringArray()
		for a: Variant in taught:
			var def := GameData.get_action(str(a))
			names.append(def.display_name if def != null else str(a))
		line += " (new ability: %s)" % ", ".join(names)
	Events.hud_message.emit(line, "good")
	r["learned"] = taught
	r["message"] = line
	last_result = r
	return r


## {ok, reason (ANCESTRY_REASONS), message}: ancestry `id` can be chosen now - not chosen yet, a
## choosable ancestry (not the neutral one), the Old Kingdom opened, out of combat.
func can_choose_ancestry(id: String) -> Dictionary:
	if ancestry_chosen:
		return _fail("chosen", "Your ancestry is chosen: you are %s." % ancestry_name())
	if not Talents.is_choosable(id):
		return _fail("unknown", "There is no ancestry '%s' to choose." % id)
	if not world_opened():
		return _fail("not_yet", "Your blood awakens when you reach the Old Kingdom.")
	if player.entity.combatant.pools.in_combat():
		return _fail("combat", "Not during combat.")
	return {"ok": true, "reason": "", "message": ""}


## Chooses ancestry `id`, once (can_choose_ancestry first): its attribute points join the
## attributes (attributes_changed), its passives are rebuilt, its signature is learned (source
## "ancestry"), the flag ancestry.chosen is set (to the id), ancestry_chosen and a HUD line are
## emitted. {ok, reason, message, signature (learned id or "")}.
func choose_ancestry(id: String) -> Dictionary:
	var check := can_choose_ancestry(id)
	if not check.ok:
		check["signature"] = ""
		last_result = check
		return check
	ancestry = id
	ancestry_chosen = true
	var bonus := Talents.attribute_bonus_of(id)
	if not bonus.is_empty():
		var attrs := attributes()
		for key: String in bonus:
			attrs[key] = int(attrs[key]) + int(bonus[key])
		player.entity.combatant.set_attributes(attrs)
		Events.attributes_changed.emit(Sim.tick)
	rebuild_passives()
	var sig := Talents.signature_of(id)
	var taught := sig != "" and learn_ability(sig, "ancestry")
	WorldState.try_set_flag(Talents.CHOSEN_FLAG, id)
	Events.ancestry_chosen.emit(Sim.tick, id)
	var line := "Your blood answers: you are %s" % ancestry_name()
	Events.hud_message.emit(line, "good")
	last_result = {"ok": true, "reason": "", "message": line, "signature": sig if taught else ""}
	return last_result


## The talents' and the ancestry's passive lines ("Armour +25", "Stamina costs -15%", ...).
func passive_lines() -> PackedStringArray:
	var c := player.entity.combatant
	var out := Talents.modifier_lines(c.passives)
	for t: Variant in c.passive_resistances:
		out.append("%s resistance +%d%%" % [str(t).capitalize(), roundi(float(c.passive_resistances[t]) * 100.0)])
	return out


## Folds the learned talents' and the ancestry's modifiers into the combatant (Combatant.set_passives),
## then brings the two things the combatant cannot change itself up to date: the costs and
## cooldowns of the library's actions and the profile's grab reach. Called on every talent and
## ancestry change, on load (apply_state) and on every profile change (growth).
func rebuild_passives() -> void:
	if player == null or player.entity == null:
		return
	var c := player.entity.combatant
	var p := Talents.passives_for(talents, ancestry if ancestry_chosen else "")
	c.set_passives(p.modifiers, p.resistances)
	if c.action_source == null:
		c.action_source = weakref(player.controller)
	_sync_action_costs(true)
	_sync_profile_passives()


## The library's actions carry the giant's stamina cost, essence cost and cooldown multipliers:
## while any of them is not 1, every action of the controller's library is a copy of its record's
## ActionDef with stamina_cost, essence_cost and cooldown_s scaled (the controller checks and pays
## those, the hotbar shows them, a refunded grab gives them back); otherwise the shared ActionDefs.
## A copy is remade when the multipliers change, when its record was refilled (a test override) or
## when force is set; an action added to the library since the last sync is copied at the next.
func _sync_action_costs(force: bool = false) -> void:
	var c := player.entity.combatant
	var m := Vector3(c.stamina_cost_mult(), c.essence_cost_mult(), c.cooldown_mult())
	var lib: Dictionary = player.controller.library
	if not force and m == _cost_mults and lib.size() == _cost_lib_size:
		return
	var neutral := m == Vector3.ONE
	for id: Variant in lib.keys():
		var base := GameData.get_action(str(id))
		var cur: ActionDef = lib[id]
		if base == null or cur == null:
			continue
		if neutral:
			if cur != base:
				lib[id] = base
		elif cur == base or force or m != _cost_mults or not is_same(cur.params, base.params):
			lib[id] = scaled_action(base, m)
	_cost_mults = m
	_cost_lib_size = lib.size()


## A copy of `base` whose stamina cost, essence cost and cooldown are multiplied by m.x, m.y, m.z.
static func scaled_action(base: ActionDef, m: Vector3) -> ActionDef:
	var a := ActionDef.from_dict(base.params)
	a.stamina_cost = base.stamina_cost * m.x
	a.essence_cost = base.essence_cost * m.y
	a.cooldown_s = base.cooldown_s * m.z
	return a


## The giant's profile with the grab reach the passives add (Iron Grip): a copy of the growth record
## with grab_reach_m raised (PlayerGrab reads it there), or the record itself when nothing is added.
func _sync_profile_passives() -> void:
	var add := player.entity.combatant.grab_reach_add()
	_profile_reach_add = add
	if _profile_base.is_empty():
		_profile_base = player.profile
	if add == 0.0:
		_profile_copy = {}
		if not is_same(player.profile, _profile_base):
			player.profile = _profile_base
		return
	var p := _profile_base.duplicate()
	var reach := float(_profile_base.get("grab_reach_m", float(_profile_base.get("melee_reach_m", 3.5)) + 0.5))
	p["grab_reach_m"] = reach + add
	_profile_copy = p
	player.profile = p


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
	# P33: the learned talents (unknown ids left out), the ancestry's choice (the ancestry itself:
	# every ancestry but the neutral one is chosen, as CharacterState normalises it), then the passives.
	if typeof(state.get("talents")) == TYPE_ARRAY:
		var known: Array = []
		for id: Variant in state.talents:
			if not Talents.record(str(id)).is_empty() and not known.has(str(id)):
				known.append(str(id))
		talents = known
	ancestry_chosen = ancestry != CharacterState.DEFAULT_ANCESTRY
	rebuild_passives()


func capture_state(out: Dictionary) -> void:
	out["level"] = level if gated else UNGATED_LEVEL
	out["xp"] = xp
	out["unspent_attribute_points"] = unspent_attribute_points
	out["talent_points"] = talent_points
	out["attributes"] = attributes()
	out["level_exempt"] = level_exempt_ids()
	out["ancestry"] = ancestry
	out["talents"] = talents.duplicate()   # P33
	out["ancestry_chosen"] = ancestry_chosen


func debug_info(out: Dictionary) -> void:
	var prog := level_progress()
	out["progression"] = "Lv %d%s  %d XP (%d / %d)  points %d  talents %d" % [level,
		"" if gated else " (ungated)", xp, int(prog[0]), int(prog[1]), unspent_attribute_points, talent_points]
	# P33: what the talents and the ancestry add (the passives, never statuses).
	out["talents"] = "%s  %d learned  %s" % [ancestry_name() if ancestry_chosen else "no ancestry",
		talents.size(), ", ".join(passive_lines())]
