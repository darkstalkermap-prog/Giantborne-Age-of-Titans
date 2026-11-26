class_name SettlementWork
extends RefCounted
## C4: a settlement's development, live - SettlementRules (pure) on the session's state (GameSession.expansion, saved
## with every checkpoint), the world's flags (WorldState: what the world's FlagVisibility elements, forges, waystones,
## encounters and dialogue read), the inventory, the events (Events.settlement_*: the HUD's toasts, the cue router's
## sounds, the screens) and a checkpoint after each change, so the work outlives a reload.
##   * deliver: a load the giant carried set down at a project's site (PlayerHaul): the site's stack grows (its haul
##     flag), "1 of 2 great timbers at the hall";
##   * give: materials from the inventory to a project (the settlement panel);
##   * raise: the project raised by the giant at its site once its needs are met (SettlementSite): its flag at once;
##     the tier's when it was the tier's last project (Events.settlement_tier: the toast, the horn);
##   * trade, rest: what an open tier offers (the panel, the hall's fire);
##   * mend_flags: a level loading puts back any flag the state holds that the world lacks (a save written between the
##     state's change and its flags'), never lowering one.
## Every change is refused out of play by the same blockers as the armour's (Armour.change_blocked: no fight, no enemy
## hunting the giant), except a load set down: the giant may drop a stone in a fight.

const CHECKPOINT_REASON := "settlement"


## The state of a settlement record in this game (made when missing).
static func state(rec: Dictionary) -> Dictionary:
	return SettlementRules.state_of(GameSession.expansion, rec)


static func context() -> Dictionary:
	return Quests.condition_context()


static func status(rec: Dictionary, pid: String) -> Dictionary:
	return SettlementRules.project_status(rec, pid, state(rec), context())


## A load set down at project `pid`'s site: {"ok", "message", "count", "want"}.
static func deliver(rec: Dictionary, pid: String, load_id: String) -> Dictionary:
	var st := state(rec)
	var p := SettlementRules.project(rec, pid)
	var want := 0
	for n: Dictionary in p.get("needs", []):
		if str(n.get("kind", "")) == "haul" and str(n.get("load", "")) == load_id:
			want = int(n.get("count", 1))
	var n := SettlementRules.deliver(rec, st, pid, load_id)
	if n < 0:
		return {"ok": false, "message": "%s needs no %s." % [str(p.get("name", "This work")),
			SettlementRules.load_name(rec, load_id)], "count": 0, "want": want}
	WorldState.set_flag(SettlementRules.haul_flag(rec, pid, load_id, n), true)
	var msg := "%s: %d of %d %s set down for %s." % [str(rec.display_name), n, want,
		SettlementRules.load_name(rec, load_id, want), str(p.get("name", pid)).to_lower()]
	Events.settlement_progress.emit(Sim.tick, str(rec.id), pid, "haul:" + load_id)
	Events.hud_message.emit(msg, "good")
	_after_change(rec, pid)
	return {"ok": true, "message": msg, "count": n, "want": want}


## Gives what is still wanted of `item` to project `pid` from the inventory: {"ok", "message", "count"}.
static func give(rec: Dictionary, pid: String, item: String) -> Dictionary:
	var blocked := Armour.change_blocked()
	if blocked != "":
		return {"ok": false, "message": blocked, "count": 0}
	var st := state(rec)
	var check := SettlementRules.can_give(rec, st, pid, item, WorldState.inventory)
	if not bool(check.ok):
		return {"ok": false, "message": str(check.message), "count": 0}
	var count := int(check.count)
	if not WorldState.remove_item(item, count, "settlement:" + pid):
		return {"ok": false, "message": "You do not carry enough.", "count": 0}
	SettlementRules.give(st, pid, item, count)
	var nm := str(GameData.get_record(item).get("display_name", item))
	var msg := "Given to %s: %d %s." % [str(rec.display_name), count, nm]
	Events.settlement_progress.emit(Sim.tick, str(rec.id), pid, "give:" + item)
	_after_change(rec, pid)
	return {"ok": true, "message": msg, "count": count}


## Whether the giant may raise project `pid` now ({"ok", "reason", "message"}).
static func can_raise(rec: Dictionary, pid: String) -> Dictionary:
	var check := SettlementRules.can_raise(rec, state(rec), pid, context())
	if bool(check.ok):
		var blocked := Armour.change_blocked()
		if blocked != "":
			return {"ok": false, "reason": "fight", "message": blocked}
	return check


## Raises project `pid` (its needs met): {"ok", "message", "tier_up"}. `auto`: an auto project raised by the folk behind
## the giant's back (SettlementWatch) - no fight rule, no raising sound or dust.
static func raise(rec: Dictionary, pid: String, auto := false) -> Dictionary:
	var check := SettlementRules.can_raise(rec, state(rec), pid, context()) if auto else can_raise(rec, pid)
	if not bool(check.ok):
		return {"ok": false, "message": str(check.message), "tier_up": -1}
	var st := state(rec)
	var r := SettlementRules.raise(rec, st, pid)
	for f: String in r.flags:
		WorldState.set_flag(f, r.flags[f])
	var p := SettlementRules.project(rec, pid)
	var msg := str(p.get("raised_text", "%s is raised." % str(p.get("name", pid))))
	if not auto:
		Events.settlement_raised.emit(Sim.tick, str(rec.id), pid)
	var up := int(r.tier_up)
	if up > 0:
		_mirror(rec, st)
		Events.settlement_tier.emit(Sim.tick, str(rec.id), up)
		Events.hud_message.emit("%s stands at %s." % [str(rec.display_name), SettlementRules.tier_name(rec, up)], "good")
	GameSession.request_checkpoint(CHECKPOINT_REASON)
	return {"ok": true, "message": msg, "tier_up": up}


## Makes trade `tid` once: {"ok", "message"}.
static func trade(rec: Dictionary, tid: String) -> Dictionary:
	var blocked := Armour.change_blocked()
	if blocked != "":
		return {"ok": false, "message": blocked}
	var check := SettlementRules.can_trade(rec, state(rec), tid, WorldState.inventory)
	if not bool(check.ok):
		return {"ok": false, "message": str(check.message)}
	var t := SettlementRules.trade(rec, tid)
	for g: Dictionary in t.get("give", []):
		WorldState.remove_item(str(g.item), int(g.count), "trade:" + tid)
	for g: Dictionary in t.get("get", []):
		WorldState.add_item(str(g.item), int(g.count), "trade:" + tid)
	GameSession.request_checkpoint(CHECKPOINT_REASON)
	return {"ok": true, "message": "Traded: %s." % SettlementRules.trade_text(t)}


## Rest by a settlement's fire (SettlementRest): the pools to their maxima and every debuff gone (as a shrine's rest),
## then a checkpoint (its respawn `respawn`: the settlement's waystone). {"ok", "message"}.
static func rest(player: GiantPlayer, world_id: String, respawn := "") -> Dictionary:
	if player == null or not player.entity.is_alive():
		return {"ok": false, "message": "The dead cannot rest."}
	var c := player.entity.combatant
	var pools := c.pools
	var missing := pools.health_max - pools.health
	if missing > 0.0:
		player.entity.heal(missing, world_id)
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	for id: String in c.statuses.active_ids():
		var def := GameData.get_status(id)
		if def != null and def.tags.has("Debuff"):
			c.statuses.remove(id)
			Events.status_expired.emit(Sim.tick, player.entity.entity_id, id)
	Events.shrine_rested.emit(Sim.tick, world_id)
	GameSession.request_checkpoint(CHECKPOINT_REASON, respawn)
	return {"ok": true, "message": "You rest by the fire. Health, stamina and essence are restored."}


## The world flags the state holds and the world lacks, set (a level loading; SettlementWatch). Returns how many.
static func mend_flags(level_id: String) -> int:
	var n := 0
	for rec: Dictionary in SettlementRules.records():
		if level_id != "" and str(rec.get("level", "")) != level_id:
			continue
		var st := state(rec)
		# the world's tier flags raise the state's tier (never lower it): an older save's flags
		st.level = maxi(SettlementRules.tier_of(st), SettlementRules.tier_from_flags(rec, WorldState.flags))
		var owed := SettlementRules.flags_owed(rec, st, WorldState.flags)
		for f: String in owed:
			WorldState.set_flag(f, owed[f])
			n += 1
		_mirror(rec, st)
	return n


## The state's `flags` mirror of the tier ("tier_<n>": true) for the Character menu and the save's readers.
static func _mirror(rec: Dictionary, st: Dictionary) -> void:
	SettlementRules.normalize(st)
	for k in range(1, SettlementRules.tier_of(st) + 1):
		st.flags["tier_%d" % k] = true


static func _after_change(rec: Dictionary, pid: String) -> void:
	var s := status(rec, pid)
	if bool(s.get("ready", false)) and not bool(s.get("raised", false)):
		Events.settlement_ready.emit(Sim.tick, str(rec.id), pid)
	GameSession.request_checkpoint(CHECKPOINT_REASON)


## Debug and tests (the capture tour, the gate walk's checks): settlement `rec` at tier `n` at once - every project of
## the tiers up to n raised, their flags and the tier's, and (`settled`) each tier's life come. Lowers nothing it
## does not set: a later tier's projects keep their state. Returns the flags set.
static func debug_set_tier(rec: Dictionary, n: int, settled := true) -> Dictionary:
	var st := state(rec)
	var flags := {}
	for k in range(1, mini(n, SettlementRules.max_tier(rec)) + 1):
		for p: Dictionary in SettlementRules.tier_rec(rec, k).get("projects", []):
			SettlementRules.project_state(st, str(p.id)).raised = true
			flags[SettlementRules.project_flag(rec, str(p.id))] = true
		if settled:
			flags[SettlementRules.settled_flag(rec, k)] = true
	st.level = maxi(SettlementRules.tier_of(st), n)
	flags.merge(SettlementRules.tier_flags(rec, SettlementRules.tier_of(st)), true)
	for f: String in flags:
		WorldState.set_flag(f, flags[f])
	_mirror(rec, st)
	return flags
