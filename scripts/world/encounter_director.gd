class_name EncounterDirector
extends Node
## Spawns a level's enemies from `encounter` records (plan §2.7.4, §3.10, decision 2), with
## stable entity ids from the data. One per level: LevelRoot/EncounterDirector. Group
## "encounter_director" (and "debug_info_providers" for the F3 panel).
##
## Runs in Sim's PRE_ACTORS phase (order 10). Every lod.check_ticks (30) ticks of the level
## record it walks the level's encounters in id order:
##   * a dormant encounter whose flags allow it (requires_flags all truthy, forbids_flags none)
##     activates when the player is within activate_radius_m of its centre (horizontally) and the
##     budget has room (or it has members that do not count); it spawns its members and emits
##     encounter_activated;
##   * an active encounter spawns members still waiting for room in the budget, leashes members
##     farther than leash_radius_m from its centre (begin_leash_return() and encounter_leashed;
##     they engage again once home), sets each member's AI LOD tier by distance to the player
##     (tier 0 within lod.near_m, 1 within lod.mid_m, else 2; engaged members stay at tier 0),
##     and deactivates once the player is beyond deactivate_radius_m and no member has been aware
##     of the player for UNAWARE_DEACTIVATE_S: its living members are freed (not killed) and come
##     back at home, at full health, on the next activation;
##   * dead members are freed corpse_free_s after death.
## Every tick, members of an alert group share awareness: while one is aware of the player, an
## unaware one is alerted (EnemyBrain.on_noise with what the aware one knows).
##
## The budget: at most max_active_enemies living, non-routed members of budgeted encounters
## (counts_toward_budget) whose definition is an enemy record exist at once; NPC spawns never
## count. Members that do not fit wait and spawn as soon as room frees up.
##
## Persistence: a death of a member with persist_death is recorded (WorldState.record_killed),
## so it never spawns again. An encounter is cleared when every member is dead or routed: the
## flag encounter.<short id>.cleared is set and encounter_cleared emitted, once; a cleared
## encounter (by its flag) never activates again. despawn() removes a living member without a
## kill; it comes back at home on the next activation (force_activate() counts as one).
##
## Spawning, before the actor enters the tree: instance the definition's scene, set its
## CombatEntity definition_id, entity_id, ai_enabled, faction, encounter_id, persist_death,
## commander, loot_table, patrol_route (the absolute path of LevelRoot.patrol_route(patrol)),
## home_position, position and yaw (level space, lifted SPAWN_LIFT_M) and the LOD tier, then add
## it under LevelRoot/Spawned. Spawns happen only inside the director's own update (the Sim
## hook, or update_now()), never from a physics callback.

signal member_spawned(encounter_id: String, entity_id: String, node: Node3D)

const GROUP := "encounter_director"
const HOOK_ORDER := 10
const DEFAULT_MAX_ACTIVE := 12
const DEFAULT_NEAR_M := 40.0
const DEFAULT_MID_M := 90.0
const DEFAULT_CHECK_TICKS := 30
const DEFAULT_CORPSE_FREE_S := 6.0
## An active encounter beyond its deactivate radius deactivates once no member has been aware of
## the player for this long (plan §3.10).
const UNAWARE_DEACTIVATE_S := 10.0
## Spawned actors start this far above their data position (never inside the floor).
const SPAWN_LIFT_M := 0.05

const DORMANT := "dormant"
const ACTIVE := "active"
const CLEARED := "cleared"

## Member statuses (member_status()).
const UNSPAWNED := "unspawned"   ## waits for an activation or for room in the budget
const SPAWNED := "spawned"       ## in the world (alive, or routed)
const DEAD := "dead"             ## killed (in this load, or recorded before it)
const DESPAWNED := "despawned"   ## removed by despawn(); returns on the next activation

## From the level record (defaults above when it has none). P14 tunes these.
var max_active_enemies := DEFAULT_MAX_ACTIVE
var near_m := DEFAULT_NEAR_M
var mid_m := DEFAULT_MID_M
var check_ticks := DEFAULT_CHECK_TICKS
var corpse_free_s := DEFAULT_CORPSE_FREE_S
## Seconds without an aware member before a distant active encounter deactivates (tests may
## shorten it).
var unaware_deactivate_s := UNAWARE_DEACTIVATE_S
## The highest active_combatant_count() seen after an update (tests, bot metrics).
var peak_active := 0

var level: LevelRoot

var _encounters: Dictionary = {}   # encounter id -> Encounter
var _order: PackedStringArray = PackedStringArray()
var _members: Dictionary = {}      # entity id -> Member
var _next_check_tick := -1
var _dirty := false
var _scenes: Dictionary = {}       # scene path -> PackedScene
var _warned: Dictionary = {}


class Encounter extends RefCounted:
	var id := ""
	var record: Dictionary = {}
	var flag := ""                 # encounter.<short id>.cleared
	var center := Vector3.ZERO     # global
	var activate_r := 0.0
	var deactivate_r := 0.0
	var leash_r := 0.0
	var alert_group := true
	var counts_budget := true
	var requires_flags: Array = []
	var forbids_flags: Array = []
	var state := "dormant"
	var members: Array = []        # Member, in spawn order
	var last_aware_tick := -1
	var activated_tick := -1
	var activations := 0
	var force_requested := false
	var cleared_emitted := false


class Member extends RefCounted:
	var entity_id := ""
	var encounter_id := ""
	var spawn: Dictionary = {}
	var definition := ""
	var budgeted := true
	var status := "unspawned"
	var node: Node3D = null
	var routed := false
	var died_tick := -1
	var free_tick := -1
	var spawn_count := 0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group("debug_info_providers")
	if not Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.connect(_on_entity_died)
	if not Events.enemy_routed.is_connected(_on_enemy_routed):
		Events.enemy_routed.connect(_on_enemy_routed)
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, _on_pre_actors, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)
	if Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.disconnect(_on_entity_died)
	if Events.enemy_routed.is_connected(_on_enemy_routed):
		Events.enemy_routed.disconnect(_on_enemy_routed)


func _ready() -> void:
	level = _find_level()
	reload_encounters()


# --------------------------------------------------------------------------- public API

## The spawned actor with this entity id (alive, or its corpse until it is freed), else null.
func spawned(entity_id: String) -> Node3D:
	var m: Member = _members.get(entity_id)
	if m == null or m.node == null or not is_instance_valid(m.node):
		return null
	return m.node


## "dormant" | "active" | "cleared" ("" for an encounter this director does not run).
func encounter_state(encounter_id: String) -> String:
	var enc: Encounter = _encounters.get(encounter_id)
	return enc.state if enc != null else ""


## Living, non-routed spawned members of budgeted encounters whose definition is an enemy.
func active_combatant_count() -> int:
	var n := 0
	for id in _order:
		for m: Member in (_encounters[id] as Encounter).members:
			if m.budgeted and m.status == SPAWNED and not m.routed and _alive(m.node):
				n += 1
	return n


## Activates an encounter at the next update regardless of the player's distance and its flags
## (tests and the bot); a cleared encounter stays cleared. On an active encounter this is a
## re-activation: members removed by despawn() come back. Spawning still respects the budget.
func force_activate(encounter_id: String) -> void:
	var enc: Encounter = _encounters.get(encounter_id)
	if enc == null:
		push_warning("EncounterDirector: unknown encounter '%s'" % encounter_id)
		return
	if enc.state == CLEARED:
		return
	enc.force_requested = true
	_dirty = true


## Removes a living member without recording a kill (the boss arena clears intruders this way).
## It returns, at home and at full health, on the encounter's next activation. The node leaves
## the tree at the end of the frame (this may be called from a physics callback).
func despawn(entity_id: String) -> void:
	var m: Member = _members.get(entity_id)
	if m == null or m.status != SPAWNED:
		return
	var n := m.node
	m.node = null
	m.status = DESPAWNED
	m.routed = false
	if n != null and is_instance_valid(n):
		if "ai_enabled" in n:
			n.set("ai_enabled", false)
		_free_node.call_deferred(n)


## Runs a full update now (tests, the bot): activation, spawns, leash, LOD, deactivation and
## corpses, as the Sim hook does every check_ticks.
func update_now() -> void:
	_share_alerts(Sim.tick)
	_update(Sim.tick)


## Ids of the encounters this director runs, in id order.
func encounter_ids() -> PackedStringArray:
	return _order.duplicate()


## Entity ids of an encounter's members, in spawn order.
func members_of(encounter_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var enc: Encounter = _encounters.get(encounter_id)
	if enc != null:
		for m: Member in enc.members:
			out.append(m.entity_id)
	return out


## "unspawned" | "spawned" | "dead" | "despawned" ("" for an unknown id).
func member_status(entity_id: String) -> String:
	var m: Member = _members.get(entity_id)
	return m.status if m != null else ""


## How many times a member was spawned in this load (tests).
func spawn_count(entity_id: String) -> int:
	var m: Member = _members.get(entity_id)
	return m.spawn_count if m != null else 0


## Re-reads the level record and this level's encounter records (and WorldState: kills and
## cleared flags). Everything spawned so far is freed first.
func reload_encounters() -> void:
	for id in _order:
		for m: Member in (_encounters[id] as Encounter).members:
			if m.node != null and is_instance_valid(m.node):
				_free_node(m.node)
	_encounters.clear()
	_members.clear()
	_order = PackedStringArray()
	_load_settings()
	if level == null:
		return
	var origin := level.global_transform if level.is_inside_tree() else level.transform
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if str(rec.get("level", "")) != level.level_id:
			continue
		var enc := Encounter.new()
		enc.id = str(rec.get("id", ""))
		enc.record = rec
		enc.flag = cleared_flag(enc.id)
		enc.center = origin * _vec3(rec.get("center_m"))
		enc.activate_r = float(rec.get("activate_radius_m", 0.0))
		enc.deactivate_r = float(rec.get("deactivate_radius_m", enc.activate_r))
		enc.leash_r = float(rec.get("leash_radius_m", 0.0))
		enc.alert_group = bool(rec.get("alert_group", true))
		enc.counts_budget = bool(rec.get("counts_toward_budget", true))
		enc.requires_flags = (rec.get("requires_flags", []) as Array).duplicate()
		enc.forbids_flags = (rec.get("forbids_flags", []) as Array).duplicate()
		for s: Variant in rec.get("spawns", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var m := Member.new()
			m.entity_id = str(s.get("entity_id", ""))
			m.encounter_id = enc.id
			m.spawn = s
			m.definition = str(s.get("definition", ""))
			var def := GameData.get_record(m.definition)
			m.budgeted = enc.counts_budget and str(def.get("type", "")) == "enemy"
			if WorldState.is_killed(m.entity_id):
				m.status = DEAD
			if m.entity_id == "" or _members.has(m.entity_id):
				continue   # the validator reports duplicates; the first one wins here
			_members[m.entity_id] = m
			enc.members.append(m)
		_encounters[enc.id] = enc
		_order.append(enc.id)
	_order.sort()
	for id in _order:
		var enc: Encounter = _encounters[id]
		if Waystone.flag_truthy(WorldState.get_flag(enc.flag)):
			enc.state = CLEARED
			enc.cleared_emitted = true
		elif _all_dead(enc):
			_mark_cleared(enc, Sim.tick)   # every member was killed before this load
	_dirty = true


## The world flag set when an encounter is cleared: "encounter.<id without 'encounter.'>.cleared".
static func cleared_flag(encounter_id: String) -> String:
	return "encounter.%s.cleared" % encounter_id.trim_prefix("encounter.")


## Lines for the F3 debug panel (group debug_info_providers).
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var counts := {DORMANT: 0, ACTIVE: 0, CLEARED: 0}
	for id in _order:
		var st: String = (_encounters[id] as Encounter).state
		counts[st] = int(counts.get(st, 0)) + 1
	lines.append("DIRECTOR %s  combatants %d/%d  encounters %d active, %d dormant, %d cleared" % [
		level.level_id if level != null else "?", active_combatant_count(), max_active_enemies,
		counts[ACTIVE], counts[DORMANT], counts[CLEARED]])
	for id in _order:
		var enc: Encounter = _encounters[id]
		if enc.state != ACTIVE:
			continue
		var tally := {UNSPAWNED: 0, SPAWNED: 0, DEAD: 0, DESPAWNED: 0}
		var routed := 0
		for m: Member in enc.members:
			tally[m.status] = int(tally.get(m.status, 0)) + 1
			if m.routed:
				routed += 1
		lines.append("  %s: %d up, %d waiting, %d dead, %d routed%s" % [id, tally[SPAWNED],
			int(tally[UNSPAWNED]) + int(tally[DESPAWNED]), tally[DEAD], routed,
			"  (alert)" if Sim.tick - enc.last_aware_tick <= 1 else ""])
	return lines


# --------------------------------------------------------------------------- the update

func _on_pre_actors(tick: int) -> void:
	if not is_inside_tree():
		return
	_share_alerts(tick)
	if _dirty or tick >= _next_check_tick:
		_update(tick)


func _update(tick: int) -> void:
	_dirty = false
	_next_check_tick = tick + maxi(1, check_ticks)
	var player := _player()
	var ppos := player.global_position if player != null else Vector3.INF
	for id in _order:
		var enc: Encounter = _encounters[id]
		_refresh_nodes(enc)
		_free_due_corpses(enc, tick)
		match enc.state:
			DORMANT:
				if enc.force_requested:
					_activate(enc, tick, ppos)
				elif ppos != Vector3.INF and flags_allow(enc.record) \
						and _flat_dist(ppos, enc.center) <= enc.activate_r and _can_activate(enc):
					_activate(enc, tick, ppos)
			ACTIVE:
				if enc.force_requested:
					_reactivate(enc, tick)
				_update_active(enc, tick, ppos)
			CLEARED:
				_update_cleared(enc, ppos)
		enc.force_requested = false
	peak_active = maxi(peak_active, active_combatant_count())


## True when every requires_flags flag is truthy and no forbids_flags flag is.
static func flags_allow(rec: Dictionary) -> bool:
	for f: Variant in rec.get("requires_flags", []):
		if not Waystone.flag_truthy(WorldState.get_flag(str(f))):
			return false
	for f: Variant in rec.get("forbids_flags", []):
		if Waystone.flag_truthy(WorldState.get_flag(str(f))):
			return false
	return true


func _activate(enc: Encounter, tick: int, ppos: Vector3) -> void:
	enc.state = ACTIVE
	enc.activated_tick = tick
	enc.last_aware_tick = tick   # a fresh activation gets the full grace before deactivating
	enc.activations += 1
	for m: Member in enc.members:
		if m.status == DESPAWNED:
			m.status = UNSPAWNED
	_spawn_waiting(enc, tick, ppos)
	Events.encounter_activated.emit(tick, enc.id)


func _reactivate(enc: Encounter, tick: int) -> void:
	enc.last_aware_tick = tick
	for m: Member in enc.members:
		if m.status == DESPAWNED:
			m.status = UNSPAWNED


func _update_active(enc: Encounter, tick: int, ppos: Vector3) -> void:
	if _any_aware(enc):
		enc.last_aware_tick = tick
	if ppos != Vector3.INF and _flat_dist(ppos, enc.center) > enc.deactivate_r \
			and tick - enc.last_aware_tick >= ActionDef.seconds_to_ticks(unaware_deactivate_s):
		_deactivate(enc)
		return
	_spawn_waiting(enc, tick, ppos)
	_check_leash(enc, tick)
	if ppos != Vector3.INF:
		_apply_lod(enc, ppos)


## Living members are freed (not killed): they come back at home, at full health, on the next
## activation. Corpses are freed too.
func _deactivate(enc: Encounter) -> void:
	for m: Member in enc.members:
		match m.status:
			SPAWNED:
				_free_node(m.node)
				m.node = null
				m.status = UNSPAWNED
				m.routed = false
			DEAD:
				if m.node != null:
					_free_node(m.node)
					m.node = null
			DESPAWNED:
				m.status = UNSPAWNED
	enc.state = DORMANT


## A cleared encounter's routed survivors are freed once the player is beyond the deactivate
## radius (they fled; the encounter never comes back).
func _update_cleared(enc: Encounter, ppos: Vector3) -> void:
	if ppos == Vector3.INF or _flat_dist(ppos, enc.center) <= enc.deactivate_r:
		return
	for m: Member in enc.members:
		if m.status == SPAWNED and m.node != null:
			_free_node(m.node)
			m.node = null
			m.status = UNSPAWNED


## Spawns the members still waiting, in spawn order, while the budget has room (members that do
## not count toward it always spawn). Killed ones are skipped for good.
func _spawn_waiting(enc: Encounter, tick: int, ppos: Vector3) -> void:
	for m: Member in enc.members:
		if m.status != UNSPAWNED:
			continue
		if WorldState.is_killed(m.entity_id):
			m.status = DEAD
			continue
		if m.budgeted and active_combatant_count() >= max_active_enemies:
			continue
		_spawn(enc, m, tick, ppos)
	if _all_dead(enc):
		_check_cleared(enc, tick)


func _can_activate(enc: Encounter) -> bool:
	var waiting := false
	for m: Member in enc.members:
		if m.status != UNSPAWNED and m.status != DESPAWNED:
			continue
		if WorldState.is_killed(m.entity_id):
			continue
		waiting = true
		if not m.budgeted:
			return true
	return waiting and active_combatant_count() < max_active_enemies


func _check_leash(enc: Encounter, tick: int) -> void:
	if enc.leash_r <= 0.0:
		return
	for m: Member in enc.members:
		if m.status != SPAWNED or m.routed or not _alive(m.node):
			continue
		var n := m.node
		if not n.has_method("begin_leash_return"):
			continue
		if (n.has_method("is_held") and n.call("is_held")) or (n.has_method("is_returning") and n.call("is_returning")):
			continue
		var brain: Variant = n.get("brain")
		if brain is EnemyBrain and (brain as EnemyBrain).state in [EnemyBrain.AIState.FLEE,
				EnemyBrain.AIState.ROUTED, EnemyBrain.AIState.DEAD, EnemyBrain.AIState.RETURN]:
			continue
		if _flat_dist(n.global_position, enc.center) > enc.leash_r:
			n.call("begin_leash_return")
			Events.encounter_leashed.emit(tick, enc.id, m.entity_id)


func _apply_lod(enc: Encounter, ppos: Vector3) -> void:
	for m: Member in enc.members:
		if m.status != SPAWNED or not _alive(m.node) or not m.node.has_method("set_lod_tier"):
			continue
		m.node.call("set_lod_tier", lod_tier_for(m.node.global_position, ppos, _engaged(m.node)))


## The AI LOD tier for an actor at `pos` with the player at `ppos`: 0 within near_m (or when
## engaged), 1 within mid_m, else 2.
func lod_tier_for(pos: Vector3, ppos: Vector3, engaged: bool) -> int:
	if engaged:
		return 0
	var d := pos.distance_to(ppos)
	if d <= near_m:
		return 0
	return 1 if d <= mid_m else 2


## Alert groups share awareness (every tick): while one living member of an active alert-group
## encounter is aware of the player, each unaware one hears it (on_noise, certain) with what the
## aware one knows, and wakes to LOD tier 0. Returning (leashed) and routed members are left out.
func _share_alerts(tick: int) -> void:
	for id in _order:
		var enc: Encounter = _encounters[id]
		if enc.state != ACTIVE:
			continue
		var source: EnemyBrain = null
		for m: Member in enc.members:
			var b := _brain_of(m)
			if b != null and b.aware and not _returning(m.node):
				source = b
				break
		if source == null:
			continue
		enc.last_aware_tick = tick
		if not enc.alert_group:
			continue
		var target := source.target_id if source.target_id != "" else "player"
		for m: Member in enc.members:
			var b := _brain_of(m)
			if b == null or b.aware or _returning(m.node) or b.state in [EnemyBrain.AIState.FLEE,
					EnemyBrain.AIState.ROUTED, EnemyBrain.AIState.DEAD, EnemyBrain.AIState.RETURN]:
				continue
			b.on_noise(tick, source.last_known, target, true)
			if m.node.has_method("set_lod_tier"):
				m.node.call("set_lod_tier", 0)


# --------------------------------------------------------------------------- spawning

func _spawn(enc: Encounter, m: Member, tick: int, ppos: Vector3) -> bool:
	if level == null or not level.is_inside_tree():
		return false
	if Sim.get_entity(m.entity_id) != null:
		# An earlier instance has not left the tree yet (or a placed actor uses this id).
		_warn_once("busy:" + m.entity_id, "EncounterDirector: '%s' is still in the world; spawn retried later" % m.entity_id)
		return false
	var def := GameData.get_record(m.definition)
	var packed := _scene(str(def.get("scene", "")))
	if packed == null:
		_warn_once("scene:" + m.definition, "EncounterDirector: %s (%s) has no loadable scene; not spawned" % [
			m.definition, m.entity_id])
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	var s := m.spawn
	var ce := node.get_node_or_null("CombatEntity")
	if ce != null and "definition_id" in ce:
		ce.set("definition_id", m.definition)
	_set_if(node, "entity_id", m.entity_id)
	_set_if(node, "ai_enabled", bool(s.get("ai_enabled", true)))
	_set_if(node, "faction", str(s.get("faction", "")))
	_set_if(node, "encounter_id", enc.id)
	_set_if(node, "persist_death", bool(s.get("persist_death", true)))
	_set_if(node, "commander", bool(s.get("commander", false)))
	_set_if(node, "loot_table", str(s.get("loot_table", "")))
	var patrol := str(s.get("patrol", ""))
	if patrol != "":
		var route := level.patrol_route(patrol)
		if route != null:
			_set_if(node, "patrol_route", route.get_path())
		else:
			_warn_once("patrol:" + patrol, "EncounterDirector: %s has no patrol route '%s' in %s" % [
				m.entity_id, patrol, level.level_id])
	var parent := level.spawn_parent()
	var yaw := deg_to_rad(float(s.get("yaw_deg", 0.0)))
	var world := level.global_transform * Transform3D(Basis(Vector3.UP, yaw),
		_vec3(s.get("position_m")) + Vector3.UP * SPAWN_LIFT_M)
	node.transform = parent.global_transform.affine_inverse() * world
	_set_if(node, "home_position", world.origin)
	if node.has_method("set_lod_tier") and ppos != Vector3.INF:
		node.call("set_lod_tier", lod_tier_for(world.origin, ppos, false))
	node.name = m.entity_id.validate_node_name()
	parent.add_child(node)
	m.node = node
	m.status = SPAWNED
	m.routed = false
	m.died_tick = -1
	m.free_tick = -1
	m.spawn_count += 1
	member_spawned.emit(enc.id, m.entity_id, node)
	return true


func _scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


# --------------------------------------------------------------------------- deaths, routs, clearing

func _on_entity_died(tick: int, entity_id: String, _killer_id: String) -> void:
	var m: Member = _members.get(entity_id)
	if m == null or m.status != SPAWNED:
		return
	m.status = DEAD
	m.died_tick = tick
	m.free_tick = tick + ActionDef.seconds_to_ticks(corpse_free_s)
	var persist: Variant = m.node.get("persist_death") if m.node != null and is_instance_valid(m.node) else null
	if bool(persist if persist != null else m.spawn.get("persist_death", true)):
		WorldState.record_killed(entity_id)
	_check_cleared(_encounters[m.encounter_id], tick)


func _on_enemy_routed(tick: int, entity_id: String, _encounter_id: String) -> void:
	var m: Member = _members.get(entity_id)
	if m == null or m.status != SPAWNED or m.routed:
		return
	m.routed = true
	_check_cleared(_encounters[m.encounter_id], tick)


## Cleared when every member is dead or routed (members waiting to spawn or despawned are not).
func _check_cleared(enc: Encounter, tick: int) -> void:
	if enc.state == CLEARED or enc.cleared_emitted:
		return
	for m: Member in enc.members:
		if m.status == DEAD:
			continue
		if m.status == SPAWNED and m.routed and _alive(m.node):
			continue
		return
	_mark_cleared(enc, tick)


func _mark_cleared(enc: Encounter, tick: int) -> void:
	enc.state = CLEARED
	enc.cleared_emitted = true
	WorldState.set_flag(enc.flag, true)
	Events.encounter_cleared.emit(tick, enc.id)


func _all_dead(enc: Encounter) -> bool:
	if enc.members.is_empty():
		return false
	for m: Member in enc.members:
		if m.status != DEAD:
			return false
	return true


func _free_due_corpses(enc: Encounter, tick: int) -> void:
	for m: Member in enc.members:
		if m.status == DEAD and m.node != null and m.free_tick >= 0 and tick >= m.free_tick:
			_free_node(m.node)
			m.node = null


## Members whose node vanished without the director (freed by someone else): a dead one keeps
## its status; a living one waits for the next activation, like a despawned one.
func _refresh_nodes(enc: Encounter) -> void:
	for m: Member in enc.members:
		if m.node == null:
			continue
		if is_instance_valid(m.node) and m.node.is_inside_tree():
			continue
		m.node = null
		if m.status == SPAWNED:
			m.status = DESPAWNED
			m.routed = false


# --------------------------------------------------------------------------- helpers

func _find_level() -> LevelRoot:
	var n := get_parent()
	while n != null:
		if n is LevelRoot:
			return n as LevelRoot
		n = n.get_parent()
	return get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot if is_inside_tree() else null


func _load_settings() -> void:
	var rec := level.level_record() if level != null else {}
	max_active_enemies = int(rec.get("max_active_enemies", DEFAULT_MAX_ACTIVE))
	var lod: Variant = rec.get("lod", {})
	if typeof(lod) != TYPE_DICTIONARY:
		lod = {}
	near_m = float(lod.get("near_m", DEFAULT_NEAR_M))
	mid_m = float(lod.get("mid_m", DEFAULT_MID_M))
	check_ticks = int(lod.get("check_ticks", DEFAULT_CHECK_TICKS))
	corpse_free_s = float(lod.get("corpse_free_s", DEFAULT_CORPSE_FREE_S))


func _player() -> Node3D:
	if level != null:
		return level.player()
	return get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null


func _any_aware(enc: Encounter) -> bool:
	for m: Member in enc.members:
		var b := _brain_of(m)
		if b != null and b.aware and not _returning(m.node):
			return true
	return false


## The brain of a living, non-routed spawned member, else null.
static func _brain_of(m: Member) -> EnemyBrain:
	if m.status != SPAWNED or m.routed or m.node == null or not is_instance_valid(m.node):
		return null
	if not _alive(m.node):
		return null
	return m.node.get("brain") as EnemyBrain


static func _engaged(n: Node3D) -> bool:
	var b := n.get("brain") as EnemyBrain
	return b != null and (b.aware or b.holds_token)


static func _returning(n: Node3D) -> bool:
	return n != null and n.has_method("is_returning") and bool(n.call("is_returning"))


static func _alive(n: Node3D) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	var e: Variant = n.get("entity")
	return not (e is CombatEntity) or (e as CombatEntity).is_alive()


## Takes `n` out of the tree now and frees it (only from a safe point: the director's update, a
## deferred call).
func _free_node(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	var parent := n.get_parent()
	if parent != null:
		parent.remove_child(n)
	n.queue_free()


static func _set_if(n: Node, prop: String, value: Variant) -> void:
	if prop in n:
		n.set(prop, value)


static func _vec3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _warn_once(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(text)
