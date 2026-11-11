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
##     they engage again once home; members of an intact formation excepted - their formation holds
##     them, see the P30 notes), sets each member's AI LOD tier by distance to the player
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
## count. Members that do not fit wait and spawn as soon as room frees up. A faction's armed
## members count too while their faction is hostile to the giant (P17b, FOLLOWUPS: the force
## branch's return leg put Thornwick's six guards, turned hostile, beside the ambush and the return
## patrol - 16 combatants): a neutral garrison (counts_toward_budget false) costs nothing, but once
## FactionState.is_hostile(its faction) its living members are combatants like any other, and
## the members of other encounters wait for room while they fight. A member that was already in
## the world when its faction turned is not removed (it is in the fight); new spawns wait instead.
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
##
## A streamed world (P24b, below its anchor): only encounters whose chunk is loaded and ready update,
## members in an unloading chunk are despawned (encounters centred there deactivate), spawns wait for
## a ready chunk, spawn entries filter by the giant's stage (min_stage / max_stage, at activation),
## and the director's own path queries share NavQuery's per-tick budget.
##
## The spawn hitch (P17a, FOLLOWUPS; P14 measured a 13-25 ms tick per activation and 100-150 ms
## for the first load of an archetype's scene):
##   * every scene the level's encounters can spawn is loaded when the encounters are read (at
##     level load, under the loading frame) into a cache shared by every director of the process
##     (static), so a death reload or a second level pays nothing again;
##   * the Sim hook spawns at most spawns_per_tick (SPAWNS_PER_TICK) members per tick (about 3 ms
##     each); members left over spawn on the following ticks (the encounter is active at once).
##     update_now() and force_activate() - tests, tools and the boss arena, which want the members
##     now - spawn without that limit; the budget holds either way.

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
## At most this many members spawn per tick from the Sim hook (the spawn hitch; P17a).
const SPAWNS_PER_TICK := 2

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
## Members the Sim hook spawns per tick at most (0 = no limit); update_now() and forced
## activations ignore it.
var spawns_per_tick := SPAWNS_PER_TICK

var level: LevelRoot

var _encounters: Dictionary = {}   # encounter id -> Encounter
var _order: PackedStringArray = PackedStringArray()
var _members: Dictionary = {}      # entity id -> Member
var _next_check_tick := -1
var _dirty := false
var _warned: Dictionary = {}
var _spawn_quota := -1             # spawns left in this update (-1 = no limit)
var _spawn_deferred := false       # a member waited for the quota (the next tick spawns it)

## Scene path -> PackedScene (null when it does not load), shared by every director of the
## process: preload_scenes() fills it at level load, so spawning never loads a scene.
static var _scene_cache: Dictionary = {}


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
	var enemy_def := false         # the definition is an enemy record (NPCs never count)
	var faction := ""              # the spawn's faction ("" = always hostile)
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
	_p29_ready()   # P29: stand-downs, provocation, talkers on greens, the respawn blocker
	_p32_ready()   # P32: an encounter's engines take their crews
	_p37_ready()   # P37: copies of templates (wanderers, world events) - their members' XP, targets, patrols


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


## Living, non-routed spawned members that count toward the budget (counts()): members of
## budgeted encounters whose definition is an enemy, and the armed members of a hostile faction.
func active_combatant_count() -> int:
	var n := 0
	for id in _order:
		for m: Member in (_encounters[id] as Encounter).members:
			if m.status == SPAWNED and not m.routed and counts(m) and _alive(m.node):
				n += 1
	return n


## Whether `m` counts toward the budget now: a member of a budgeted encounter whose definition is
## an enemy, or an enemy-definition member whose faction is hostile to the giant (P17b).
static func counts(m: Member) -> bool:
	if _p30_formation_member(m):
		return false   # P30: formation members count against max_formation_members instead
	return m.budgeted or (m.enemy_def and m.faction != "" and FactionState.is_hostile(m.faction))


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
## corpses, as the Sim hook does every check_ticks; every waiting member that fits the budget
## spawns at once (no spawns_per_tick limit).
func update_now() -> void:
	_share_alerts(Sim.tick)
	_update(Sim.tick, 0)


## The scene paths this level's encounters spawn (their definitions' scenes), sorted.
func scene_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _order:
		for m: Member in (_encounters[id] as Encounter).members:
			var path := str(GameData.get_record(m.definition).get("scene", ""))
			if path != "" and not out.has(path):
				out.append(path)
	out.sort()
	return out


## Loads every scene this level's encounters spawn into the shared cache (reload_encounters()
## does it at level load). Returns how many it loaded now (0 when all were cached already).
func preload_scenes() -> int:
	var loaded := 0
	for path in scene_paths():
		if not _scene_cache.has(path):
			_scene(path)
			loaded += 1
	return loaded


## True when `path` is in the shared scene cache (tests).
static func is_scene_cached(path: String) -> bool:
	return _scene_cache.has(path) and _scene_cache[path] != null


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
	_p30_clear()   # P30: every formation goes with its members
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
		if bool(rec.get("template", false)):
			continue   # P37: a template is never active by itself; the WanderDirector makes copies of it
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
			m.enemy_def = str(def.get("type", "")) == "enemy"
			m.budgeted = enc.counts_budget and m.enemy_def
			m.faction = str(s.get("faction", ""))
			if WorldState.is_killed(m.entity_id):
				m.status = DEAD
			if m.entity_id == "" or _members.has(m.entity_id):
				continue   # the validator reports duplicates; the first one wins here
			_members[m.entity_id] = m
			enc.members.append(m)
		_encounters[enc.id] = enc
		_order.append(enc.id)
	_order.sort()
	preload_scenes()   # the spawn hitch (P17a): no scene loads when an encounter activates
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
	lines.append_array(_p30_debug_lines())   # P30: the formations
	return lines


# --------------------------------------------------------------------------- the update

func _on_pre_actors(tick: int) -> void:
	if not is_inside_tree():
		return
	_share_alerts(tick)
	if _dirty or tick >= _next_check_tick:
		_update(tick, spawns_per_tick)
	_p30_tick(tick)   # P30: the formations' updates (10 Hz)
	_p29_tick(tick)   # P29: the encounters' stand_down_when


## One update. quota > 0: at most that many members spawn in it (forced activations excepted);
## members it leaves waiting spawn on the next tick (the update runs again then).
func _update(tick: int, quota := 0) -> void:
	_dirty = false
	_next_check_tick = tick + maxi(1, check_ticks)
	_spawn_quota = quota if quota > 0 else -1
	_spawn_deferred = false
	var player := _player()
	var ppos := player.global_position if player != null else Vector3.INF
	_p24b_bind()
	for id in _order:
		var enc: Encounter = _encounters[id]
		if not _p24b_live(enc):
			continue   # P24b: its chunk is not loaded and ready (a forced activation waits for it)
		_refresh_nodes(enc)
		_free_due_corpses(enc, tick)
		var forced := enc.force_requested
		var quota_left := _spawn_quota
		if forced:
			_spawn_quota = -1   # tests, tools and the boss arena want a forced encounter now
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
		if forced:
			_spawn_quota = quota_left
		enc.force_requested = false
	peak_active = maxi(peak_active, active_combatant_count())
	_spawn_quota = -1
	if _spawn_deferred:
		_dirty = true   # the members left over spawn on the next tick


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
	_p24b_filter_stage(enc)   # P24b: spawn entries outside the giant's stage sit this activation out
	_p30_activate(enc)   # P30: its formations (their stage range and the web's compositions)
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
		_p24b_skipped.erase(m.entity_id)   # P24b: the next activation filters by the stage afresh
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
	_p30_deactivate(enc)   # P30: its formations dissolve with it


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
## not count toward it always spawn) and the update's spawn quota lasts (the rest wait for the
## next tick). Killed ones are skipped for good.
func _spawn_waiting(enc: Encounter, tick: int, ppos: Vector3) -> void:
	for m: Member in enc.members:
		if m.status != UNSPAWNED:
			continue
		if WorldState.is_killed(m.entity_id):
			m.status = DEAD
			continue
		if _p24b_skipped.has(m.entity_id):
			continue   # P24b: not at this stage
		if _p30_waits_for_room(m):
			continue   # P30: the level's formation members are at max_formation_members
		if counts(m) and active_combatant_count() >= max_active_enemies:
			continue
		if _spawn_quota == 0:
			_spawn_deferred = true
			continue
		if _spawn(enc, m, tick, ppos) and _spawn_quota > 0:
			_spawn_quota -= 1
	if _all_dead(enc):
		_check_cleared(enc, tick)


func _can_activate(enc: Encounter) -> bool:
	var waiting := false
	for m: Member in enc.members:
		if m.status != UNSPAWNED and m.status != DESPAWNED:
			continue
		if WorldState.is_killed(m.entity_id):
			continue
		if not _p24b_stage_allows(m):
			continue   # P24b: a member of another stage does not make the encounter worth activating
		waiting = true
		if not counts(m):
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
		if _held(n) or _returning(n):
			continue
		if _p30_formation_holds(n):
			continue   # M7 gate: its intact formation holds it in its slot, inside the leash
		var brain: Variant = n.get("brain")
		if brain is EnemyBrain and (brain as EnemyBrain).state in [EnemyBrain.AIState.FLEE,
				EnemyBrain.AIState.ROUTED, EnemyBrain.AIState.DEAD, EnemyBrain.AIState.RETURN]:
			continue
		if _flat_dist(n.global_position, enc.center) > enc.leash_r:
			n.call("begin_leash_return")
			Events.encounter_leashed.emit(tick, enc.id, m.entity_id)


## Held or flying bodies (P07) keep their tier until they are released: their holder keeps them
## out of the simulation meanwhile.
func _apply_lod(enc: Encounter, ppos: Vector3) -> void:
	for m: Member in enc.members:
		if m.status != SPAWNED or not _alive(m.node) or not m.node.has_method("set_lod_tier") or _held(m.node):
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
			if b == null or b.aware or _returning(m.node) or _held(m.node) or b.state in [EnemyBrain.AIState.FLEE,
					EnemyBrain.AIState.ROUTED, EnemyBrain.AIState.DEAD, EnemyBrain.AIState.RETURN]:
				continue
			b.on_noise(tick, source.last_known, target, true)
			if m.node.has_method("set_lod_tier"):
				m.node.call("set_lod_tier", 0)


# --------------------------------------------------------------------------- spawning

func _spawn(enc: Encounter, m: Member, tick: int, ppos: Vector3) -> bool:
	if level == null or not level.is_inside_tree():
		return false
	if not _p24b_spawn_ground_ready(m):
		return false   # P24b: never on a chunk that is not loaded and ready (it waits for the next update)
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


## The PackedScene at `path` from the shared cache (loaded into it the first time).
func _scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scene_cache[path]


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
		if m.status == DEAD or _p24b_skipped.has(m.entity_id):
			continue
		if m.status == SPAWNED and m.routed and _alive(m.node):
			continue
		return
	_mark_cleared(enc, tick)


func _mark_cleared(enc: Encounter, tick: int) -> void:
	enc.state = CLEARED
	enc.cleared_emitted = true
	if not _p37_copies.has(enc.id):   # P37: a copy of a template saves nothing
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


## True while a giant holds (or has thrown) the actor (P07).
static func _held(n: Node3D) -> bool:
	return n != null and n.has_method("is_held") and bool(n.call("is_held"))


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


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P24b
# --- the director in a streamed world (P24b, plan M6-M9 §2.8, decision 15) ------------------------
# On a level with a ChunkStreamer (WorldRoot):
#   * an encounter's chunk is the chunk of its centre (encounter_chunk()); it updates - activates,
#     spawns, leashes, sets LOD, deactivates - only while that chunk is loaded and ready
#     (ChunkStreamer.is_ready: its navigation synced), and a forced activation waits for it;
#   * when a chunk unloads (the streamer's chunk_unloading, before any node of it is freed) every
#     living member standing in it is despawned - not killed: it comes back at home, at full health,
#     on its encounter's next activation - and every active encounter centred in it deactivates;
#   * a member spawns only when the chunk under its spawn point is loaded and ready (else it waits);
#   * spawn entries may carry min_stage / max_stage: at each activation the members outside the
#     giant's stage sit it out (they do not spawn, nor keep the encounter from being cleared);
#   * the director's own path queries (P30's formation pivots, P37's wander anchors) ask
#     nav_budget_left() and spend_nav_queries() - NavQuery's per-tick budget, shared with the actors -
#     the rest waiting a tick.
# Elsewhere (the Valley, test levels) every encounter is live and nothing changes; the stage filter
# applies wherever entries carry the keys.

var _p24b_skipped := {}       # entity id -> true: a member its entry's stage range keeps out of this activation
var _p24b_chunks := {}        # encounter id -> chunk id ("" outside the grid)
var _p24b_streamer: ChunkStreamer = null


## The streamer of this director's level (null when the level is not streamed).
func _p24b_level_streamer() -> ChunkStreamer:
	var s: Variant = level.get("streamer") if level != null else null
	return s as ChunkStreamer if s is ChunkStreamer and (s as ChunkStreamer).configured else null


## Connects to the level's streamer once it is configured (WorldRoot configures it after this
## director's _ready).
func _p24b_bind() -> void:
	var s := _p24b_level_streamer()
	if s == _p24b_streamer:
		return
	if _p24b_streamer != null and is_instance_valid(_p24b_streamer) \
			and _p24b_streamer.chunk_unloading.is_connected(_p24b_on_chunk_unloading):
		_p24b_streamer.chunk_unloading.disconnect(_p24b_on_chunk_unloading)
	_p24b_streamer = s
	_p24b_chunks.clear()
	if s != null and not s.chunk_unloading.is_connected(_p24b_on_chunk_unloading):
		s.chunk_unloading.connect(_p24b_on_chunk_unloading)


## The chunk of an encounter's centre ("" outside a streamed level's grid, or not streamed).
func encounter_chunk(encounter_id: String) -> String:
	var enc: Encounter = _encounters.get(encounter_id)
	var s := _p24b_level_streamer()
	if enc == null or s == null:
		return ""
	if not _p24b_chunks.has(encounter_id):
		_p24b_chunks[encounter_id] = s.chunk_at(enc.center)
	return str(_p24b_chunks[encounter_id])


## True when the encounter may update: always on a level that is not streamed; else while its
## chunk is loaded and ready.
func _p24b_live(enc: Encounter) -> bool:
	var s := _p24b_level_streamer()
	if s == null:
		return true
	var c := encounter_chunk(enc.id)
	return c != "" and s.is_ready(c)


## True when the ground under a member's spawn point is loaded and ready (or the level is not
## streamed).
func _p24b_spawn_ground_ready(m: Member) -> bool:
	var s := _p24b_level_streamer()
	if s == null:
		return true
	var at := level.global_transform * _vec3(m.spawn.get("position_m"))
	var c := s.chunk_at(at)
	return c != "" and s.is_ready(c)


## A chunk is about to unload: despawn every living member standing in it and deactivate every
## active encounter centred in it (their other members are freed too and come back at home).
func _p24b_on_chunk_unloading(chunk_id: String) -> void:
	var s := _p24b_level_streamer()
	if s == null:
		return
	for id in _order:
		var enc: Encounter = _encounters[id]
		if enc.state == ACTIVE and encounter_chunk(id) == chunk_id:
			_deactivate(enc)
			continue
		for m: Member in enc.members:
			if m.status == SPAWNED and _alive(m.node) and s.chunk_at(m.node.global_position) == chunk_id:
				despawn(m.entity_id)
	_dirty = true


## The giant's growth stage (0 when there is no player: nothing is filtered).
func _p24b_player_stage() -> int:
	var p := _player()
	if p != null and p.has_method("current_growth_stage"):
		return int(p.call("current_growth_stage"))
	return 0


## True when a member's spawn entry admits the giant's stage (min_stage / max_stage; absent = any).
func _p24b_stage_allows(m: Member) -> bool:
	return stage_allows(m.spawn, _p24b_player_stage())


## True when a spawn entry admits `stage` (stage 0, no player, admits everything).
static func stage_allows(spawn: Dictionary, stage: int) -> bool:
	if stage <= 0:
		return true
	if SchemaUtil.is_number(spawn.get("min_stage")) and stage < int(spawn.min_stage):
		return false
	if SchemaUtil.is_number(spawn.get("max_stage")) and stage > int(spawn.max_stage):
		return false
	return true


## At activation: the members whose entries exclude the giant's stage sit this activation out.
func _p24b_filter_stage(enc: Encounter) -> void:
	var stage := _p24b_player_stage()
	for m: Member in enc.members:
		if stage_allows(m.spawn, stage):
			_p24b_skipped.erase(m.entity_id)
		elif m.status == UNSPAWNED:
			_p24b_skipped[m.entity_id] = true


## True when a member sits the current activation out (its stage range; tests, debug).
func stage_skipped(entity_id: String) -> bool:
	return _p24b_skipped.has(entity_id)


## Path queries left this tick for the director (NavQuery's budget of the level).
func nav_budget_left() -> int:
	return NavQuery.budget_left(level)


## Counts the director's own path queries against the tick's budget.
func spend_nav_queries(n := 1) -> void:
	NavQuery.spend(level, n)

## @anchor P29
# --- stand-downs, provocation, talkers on their greens, the respawn blocker (P29) -----------------
# Plan M6-M9 §2.12, §5.9, decision 31. Hook lines: _ready (_p29_ready) and _on_pre_actors (_p29_tick).
#   * stand_down_when (an encounter's quest condition, evaluated with Quests' context): while it holds
#     - and the giant has not struck one of its members since it began to (the saved flag
#     encounter.<short>.provoked) - every member of the encounter that belongs to a faction stands
#     down whatever its faction's standing (EnemyActor's "stood_down": team NEUTRAL, at its post, guard
#     down, never aware); once it stops holding they take their faction's standing again, alerted (the
#     toll fort's riders, hostile by their faction, hold the road while the toll is pending, paid or
#     cowed; Aldmere's fort gate for a parley token, P36). Checked at every update (check_ticks) and
#     at once for a member that spawns; a faction event that resets a member is undone at the next.
#   * provocation: a connecting blow of the giant on a member of an encounter standing down sets
#     encounter.<short>.provoked; the next tick ends the stand-down (the blow itself is no faction
#     offence: a hostile-by-default faction counts none).
#   * talkers on their greens (§2.12): a talker (an npc record of role "talker") whose spawn point lies
#     inside a settlement POI with max_inner_stage and green_m stands on that green while the giant's
#     stage is above max_inner_stage: placed there when it spawns (its chunk loading, its encounter
#     activating), and moved there when the giant grows past it while it is loaded (growth happens at
#     shrines, far out of the settlements' sight).
#   * the respawn blocker: FactionState.respawn_refusal joins GameSession's blockers while this level's
#     director lives (its bound method; GameSession drops it once the director is freed).

const P29_PROVOKED_FMT := "encounter.%s.provoked"

## Encounters standing down now (encounter id -> true).
var _p29_down := {}
## A provocation was seen: the next tick re-evaluates the stand-downs.
var _p29_dirty := false
## Talkers placed on a green (entity id -> the green, global): tests, debug.
var p29_on_green := {}


## The flag a provoked encounter sets: encounter.<short id>.provoked.
static func provoked_flag(encounter_id: String) -> String:
	return P29_PROVOKED_FMT % encounter_id.trim_prefix("encounter.")


func _p29_ready() -> void:
	GameSession.register_respawn_blocker(_p29_respawn_blocker)
	if not member_spawned.is_connected(_p29_on_member_spawned):
		member_spawned.connect(_p29_on_member_spawned)
	if not Events.hit_resolved.is_connected(_p29_on_hit_resolved):
		Events.hit_resolved.connect(_p29_on_hit_resolved)
	if not Events.growth_changed.is_connected(_p29_on_growth_changed):
		Events.growth_changed.connect(_p29_on_growth_changed)


func _p29_respawn_blocker(checkpoint_id: String) -> String:
	return FactionState.respawn_refusal(checkpoint_id)


func _p29_tick(tick: int) -> void:
	if _p29_dirty or tick % maxi(1, check_ticks) == 0:
		_p29_dirty = false
		p29_update_stand_downs()


## True when the encounter's stand_down_when holds now and it was not provoked.
func p29_stands_down(encounter_id: String) -> bool:
	var enc: Encounter = _encounters.get(encounter_id)
	if enc == null or typeof(enc.record.get("stand_down_when")) != TYPE_DICTIONARY:
		return false
	if Waystone.flag_truthy(WorldState.get_flag(provoked_flag(encounter_id))):
		return false
	return QuestConditions.holds(enc.record.stand_down_when, Quests.condition_context())


## True while the encounter's members stand down (as of the last evaluation).
func p29_standing_down(encounter_id: String) -> bool:
	return _p29_down.has(encounter_id)


## Evaluates every stand_down_when now and stands its spawned faction members down or lets them go.
func p29_update_stand_downs() -> void:
	for id in _order:
		var enc: Encounter = _encounters[id]
		if typeof(enc.record.get("stand_down_when")) != TYPE_DICTIONARY:
			continue
		var was := _p29_down.has(id)
		var down := enc.state == ACTIVE and p29_stands_down(id)
		if down:
			_p29_down[id] = true
		else:
			_p29_down.erase(id)
		if not down and not was:
			continue
		for m: Member in enc.members:
			if m.status == SPAWNED and _alive(m.node):
				_p29_apply(m, down)


## Stands a faction member down (down), or gives it its faction's standing back (alerted).
func _p29_apply(m: Member, down: bool) -> void:
	var n := m.node
	if m.faction == "" or n == null or not n.has_method("_apply_standing"):
		return
	if down:
		n.call("_apply_standing", "stood_down", false)
	elif str(n.get("faction_standing")) == "stood_down":
		n.call("_apply_standing", FactionState.standing(m.faction), true)


func _p29_on_member_spawned(encounter_id: String, entity_id: String, node: Node3D) -> void:
	var m: Member = _members.get(entity_id)
	if m == null:
		return
	if p29_stands_down(encounter_id):
		_p29_down[encounter_id] = true
		_p29_apply(m, true)
	_p29_place_talker(m, node)


## A connecting blow of the giant on a member of an encounter standing down provokes it.
func _p29_on_hit_resolved(_tick: int, result: HitResult) -> void:
	if _p29_down.is_empty() or result == null or result.event == null:
		return
	var m: Member = _members.get(result.event.target_id)
	if m == null or not _p29_down.has(m.encounter_id) or not FactionState.OFFENCE_OUTCOMES.has(result.outcome):
		return
	var attacker := Sim.get_entity(result.event.attacker_id)
	if attacker == null or attacker.team != CombatEntity.Team.PLAYER:
		return
	WorldState.set_flag(provoked_flag(m.encounter_id), true)
	_p29_dirty = true


## The green a talker member stands on now (global; Vector3.INF when it keeps its spawn point): its
## spawn point's settlement POI (kind settlement, max_inner_stage and green_m) when the giant's stage
## is above max_inner_stage.
func p29_green_for(m: Member) -> Vector3:
	if m == null or str(GameData.get_record(m.definition).get("role", "")) != "talker" or level == null:
		return Vector3.INF
	var stage := _p24b_player_stage()
	var at := _vec3(m.spawn.get("position_m"))
	for poi: Dictionary in GameData.records_of_type("poi"):
		if str(poi.get("level", "")) != level.level_id or str(poi.get("kind", "")) != "settlement":
			continue
		if not poi.has("max_inner_stage") or typeof(poi.get("green_m")) != TYPE_ARRAY:
			continue
		var c := _vec3(poi.get("position_m"))
		if _flat_dist(at, c) > float(poi.get("radius_m", 0.0)) or stage <= int(poi.max_inner_stage):
			continue
		var origin := level.global_transform if level.is_inside_tree() else level.transform
		return origin * _vec3(poi.green_m)
	return Vector3.INF


func _p29_place_talker(m: Member, node: Node3D) -> void:
	var green := p29_green_for(m)
	if green == Vector3.INF or node == null or not is_instance_valid(node):
		return
	node.global_position = green + Vector3.UP * SPAWN_LIFT_M
	_set_if(node, "home_position", green)
	p29_on_green[m.entity_id] = green


## The giant grew: its loaded talkers walk out to their greens if it is now too big for their streets.
func _p29_on_growth_changed(_tick: int, entity_id: String, _old_stage: int, _new_stage: int) -> void:
	var p := _player()
	var pe: Variant = p.get("entity") if p != null else null
	if not (pe is CombatEntity) or (pe as CombatEntity).entity_id != entity_id:
		return
	for id in _order:
		for m: Member in (_encounters[id] as Encounter).members:
			if m.status == SPAWNED and _alive(m.node) and not p29_on_green.has(m.entity_id):
				_p29_place_talker(m, m.node)

## @anchor P30
# --- formations (P30, plan M6-M9 §2.10, decision 19) -----------------------------------------------
# Hook lines: _on_pre_actors (_p30_tick), _activate (_p30_activate), counts(), _spawn_waiting,
# _deactivate, reload_encounters and debug_lines.
#   * At each activation every `formations` entry of the encounter whose stage range admits the
#     giant's stage becomes a Formation (Formation.from_record), placed where its members' spawn
#     points say (the pivot that best fits their slots, the entry's yaw_deg or its first member's);
#     a formation outside the stage range sits the activation out with its members (P24b's skip set).
#     On the web (LevelRoot.is_web) each formation keeps round(members x web_formation_scale) of its
#     rank-and-file, the front rank first, and its banner (Formation.web_kept_slots); the rest sit out.
#   * Spawned members join their formation in their slot (member_spawned); a CrowdRenderer per
#     formation draws its members (group crowd_renderers).
#   * Formation members never count toward max_active_enemies (counts()): they count toward the level
#     record's max_formation_members (default 40; on the web its web_overrides' value, default 20),
#     and a member waits to spawn while the level has that many (soldiers joining a formation ask
#     p30_formation_room()).
#   * Ten times a second (Formation.UPDATE_TICKS) every formation of a live, active encounter updates
#     with the giant as its threat; a deactivation dissolves the encounter's formations.
#   * The leash (M7 gate): a member of an intact formation (formed, advancing or braced) is never
#     leashed - its formation holds it in its slot, and the data's rule (FormationRules.reach_m: every
#     slot, wherever the pivot may advance and turn, inside the encounter's leash) keeps that slot in
#     the leash. Leashing it sent it home through its own ranks while the formation still held the
#     others: the toll fort's front rank stood in RETURN behind its rear rank and the pikes never
#     braced. A member of a broken or routed formation is leashed like any other.

const P30_DEFAULT_FORMATION_CAP := 40
const P30_DEFAULT_WEB_FORMATION_CAP := 20

## The level's cap on formation members (from the level record, the web's when on the web).
var max_formation_members := P30_DEFAULT_FORMATION_CAP
var _p30_formations := {}        # formation id -> Formation (of active encounters)
var _p30_by_encounter := {}      # encounter id -> PackedStringArray of formation ids
var _p30_member_slot := {}       # entity id -> [formation id, slot]
var _p30_renderers := {}         # formation id -> CrowdRenderer
var _p30_cap_loaded := false


## The live formations of this director, by id.
func formations() -> Array[Formation]:
	var out: Array[Formation] = []
	var ids := _p30_formations.keys()
	ids.sort()
	for id: String in ids:
		out.append(_p30_formations[id])
	return out


## The formation with this id (null when none is live).
func formation(formation_id: String) -> Formation:
	return _p30_formations.get(formation_id)


## The crowd renderer of a formation (null when none).
func crowd_renderer(formation_id: String) -> CrowdRenderer:
	var r: Variant = _p30_renderers.get(formation_id)
	return r if r != null and is_instance_valid(r) else null


## True when one more formation member fits the level's cap (a soldier joining a formation).
func p30_formation_room() -> bool:
	_p30_load_cap()
	return formation_member_count() < max_formation_members


## Living, spawned formation members of every encounter (joined soldiers included).
func formation_member_count() -> int:
	var n := 0
	for id in _order:
		for m: Member in (_encounters[id] as Encounter).members:
			if m.status == SPAWNED and _alive(m.node) and _p30_formation_member(m):
				n += 1
	return n


## True when `n` stands in an intact formation (the leash leaves it to its formation; see the notes).
static func _p30_formation_holds(n: Node) -> bool:
	var f: Variant = n.get("formation") if n != null and is_instance_valid(n) else null
	return f is Formation and (f as Formation).is_intact()


## A member of a formation: its spawn names one, or it joined one.
static func _p30_formation_member(m: Member) -> bool:
	if str(m.spawn.get("formation", "")) != "":
		return true
	return m.node != null and is_instance_valid(m.node) and m.node.get("formation") != null


func _p30_waits_for_room(m: Member) -> bool:
	if str(m.spawn.get("formation", "")) == "":
		return false
	_p30_load_cap()
	return formation_member_count() >= max_formation_members


func _p30_load_cap() -> void:
	if _p30_cap_loaded or level == null:
		return
	_p30_cap_loaded = true
	var rec := level.level_record()
	max_formation_members = int(rec.get("max_formation_members", P30_DEFAULT_FORMATION_CAP))
	if LevelRoot.is_web():
		max_formation_members = int(level.web_overrides().get("max_formation_members", P30_DEFAULT_WEB_FORMATION_CAP))


func _p30_activate(enc: Encounter) -> void:
	_p30_dissolve_encounter(enc.id)
	var forms: Variant = enc.record.get("formations")
	if typeof(forms) != TYPE_ARRAY or (forms as Array).is_empty():
		return
	_p30_load_cap()
	if not member_spawned.is_connected(_p30_on_member_spawned):
		member_spawned.connect(_p30_on_member_spawned)
	var stage := _p24b_player_stage()
	var scale := clampf(float(enc.record.get("web_formation_scale", 1.0)), 0.0, 1.0)
	var origin := level.global_transform if level.is_inside_tree() else level.transform
	var ids := PackedStringArray()
	for rec: Variant in forms:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var local := str(rec.get("id", ""))
		var members: Array = []
		for m: Member in enc.members:
			if str(m.spawn.get("formation", "")) == local:
				members.append(m)
		if not stage_allows(rec, stage):
			for m: Member in members:
				if m.status == UNSPAWNED:
					_p24b_skipped[m.entity_id] = true
			continue
		var keep := []
		for m: Member in members:
			keep.append(int(m.spawn.get("slot", 0)))
		if LevelRoot.is_web() and scale < 1.0:
			keep = Formation.web_kept_slots(keep, scale)
		var f := Formation.from_record(enc.id, rec)
		f.level = level
		f.budget_left = nav_budget_left
		f.spend_budget = spend_nav_queries
		_p30_place(f, rec, members, origin)
		for m: Member in members:
			var slot := int(m.spawn.get("slot", 0))
			if not keep.has(slot):
				if m.status == UNSPAWNED:
					_p24b_skipped[m.entity_id] = true
				continue
			_p30_member_slot[m.entity_id] = [f.id, slot]
		_p30_formations[f.id] = f
		ids.append(f.id)
	_p30_by_encounter[enc.id] = ids


## The formation's home: the pivot that best fits its rank-and-file's spawn points to their slots
## (the mean of each spawn point minus its slot's offset), facing the entry's yaw_deg, else its
## first member's spawn yaw.
func _p30_place(f: Formation, rec: Dictionary, members: Array, origin: Transform3D) -> void:
	var yaw := f.home_yaw
	if not rec.has("yaw_deg"):
		for m: Member in members:
			if int(m.spawn.get("slot", 0)) != Formation.BANNER_SLOT:
				yaw = deg_to_rad(float(m.spawn.get("yaw_deg", 0.0)))
				break
	yaw += origin.basis.get_euler().y
	f.facing_yaw = yaw
	var sum := Vector3.ZERO
	var n := 0
	for m: Member in members:
		var slot := int(m.spawn.get("slot", 0))
		if slot == Formation.BANNER_SLOT:
			continue
		var at := origin * _vec3(m.spawn.get("position_m"))
		sum += at - Basis(Vector3.UP, yaw) * f.slot_local(slot)
		n += 1
	var pivot := sum / float(n) if n > 0 else origin * _p30_enc_center(f.encounter_id)
	f.place(pivot, yaw)
	for id: String in f.flee_point_ids:
		var p := _p30_marker_position(id)
		if p != Vector3.INF:
			f.flee_points.append(p)


func _p30_enc_center(encounter_id: String) -> Vector3:
	var enc: Encounter = _encounters.get(encounter_id)
	return _vec3(enc.record.get("center_m")) if enc != null else Vector3.ZERO


## A marker's position: the level's LevelMarker, else the level's world index (the world's markers
## of unloaded chunks); Vector3.INF when unknown.
func _p30_marker_position(id: String) -> Vector3:
	var m := level.marker(id) if level != null else null
	if m != null and m.is_inside_tree():
		return m.global_position
	var index: WorldIndex = level.index() if level != null and level.has_method("index") else null
	return index.position_of(id) if index != null else Vector3.INF


func _p30_on_member_spawned(_encounter_id: String, entity_id: String, node: Node3D) -> void:
	var info: Variant = _p30_member_slot.get(entity_id)
	if info == null or not (node is EnemyActor):
		return
	var f: Formation = _p30_formations.get(str(info[0]))
	if f == null or f.dissolved:
		return
	f.add_member(node as EnemyActor, int(info[1]))
	_p30_ensure_renderer(f)


func _p30_ensure_renderer(f: Formation) -> void:
	if crowd_renderer(f.id) != null or level == null:
		return
	var r := CrowdRenderer.new()
	r.name = ("Crowd_" + f.id).validate_node_name()
	r.formation = f
	level.spawn_parent().add_child(r)
	_p30_renderers[f.id] = r


func _p30_tick(tick: int) -> void:
	if _p30_formations.is_empty() or tick % Formation.UPDATE_TICKS != 0:
		return
	var player := _player()
	for enc_id: String in _p30_by_encounter.keys():
		var enc: Encounter = _encounters.get(enc_id)
		if enc == null or enc.state == DORMANT or not _p24b_live(enc):
			continue
		for fid: String in _p30_by_encounter[enc_id]:
			var f: Formation = _p30_formations.get(fid)
			if f != null:
				f.update(tick, player)


func _p30_deactivate(enc: Encounter) -> void:
	_p30_dissolve_encounter(enc.id)


func _p30_dissolve_encounter(enc_id: String) -> void:
	for fid: String in _p30_by_encounter.get(enc_id, PackedStringArray()):
		var f: Formation = _p30_formations.get(fid)
		if f != null:
			f.dissolve()
		_p30_formations.erase(fid)
		var r := crowd_renderer(fid)
		if r != null:
			r.release_all()
			r.queue_free()
		_p30_renderers.erase(fid)
		for eid: String in _p30_member_slot.keys():
			if str(_p30_member_slot[eid][0]) == fid:
				_p30_member_slot.erase(eid)
	_p30_by_encounter.erase(enc_id)


func _p30_clear() -> void:
	for enc_id: String in _p30_by_encounter.keys():
		_p30_dissolve_encounter(enc_id)
	_p30_formations.clear()
	_p30_member_slot.clear()
	_p30_cap_loaded = false


func _p30_debug_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for f in formations():
		out.append(f.debug_line())
	if not _p30_formations.is_empty():
		out.append("  formation members %d/%d" % [formation_member_count(), max_formation_members])
	return out

## @anchor P32
# --- siege engines take their crews (P32) ------------------------------------------------------------
# Plan M6-M9 §2.10, §3.16. Hook line: _ready (_p32_ready). An encounter's `engines` list names, for each
# siege engine (a SiegeEngine prop of the level, by its world id), the spawns of the encounter that
# serve it. When such a crew member spawns, the engine takes it (SiegeEngine.add_crew: the member's
# place beside the engine, its crew rules in EnemyBrain's P32 section); an engine that is not in the
# tree (another chunk, or none by that id) takes none - the crew member runs after
# EnemyBrain.CREW_WAIT_S - and a broken engine takes a crew member only to send it running.


func _p32_ready() -> void:
	if not member_spawned.is_connected(_p32_on_member_spawned):
		member_spawned.connect(_p32_on_member_spawned)


## The engine `entity_id` serves in encounter `encounter_id` ("" when it serves none).
func p32_engine_of(encounter_id: String, entity_id: String) -> String:
	var enc: Encounter = _encounters.get(encounter_id)
	if enc == null:
		return ""
	for entry: Variant in enc.record.get("engines", []):
		if typeof(entry) == TYPE_DICTIONARY and (entry.get("crew", []) as Array).has(entity_id):
			return str(entry.get("engine", ""))
	return ""


## The placed siege engine with world id `world_id` (in the tree), else null.
func p32_engine(world_id: String) -> SiegeEngine:
	if world_id == "" or not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		var e := n as SiegeEngine
		if e != null and e.world_id == world_id and e.is_inside_tree():
			return e
	return null


func _p32_on_member_spawned(encounter_id: String, entity_id: String, node: Node3D) -> void:
	var engine := p32_engine(p32_engine_of(encounter_id, entity_id))
	if engine != null and node != null and is_instance_valid(node):
		engine.add_crew(node)

## @anchor P34

## @anchor P37
# --- copies of templates: wanderers and world events (P37) --------------------------------------------
# Plan M6-M9 §2.13, decision 27. Hook lines: _ready (_p37_ready), reload_encounters (a template is skipped:
# never active by itself) and _mark_cleared (a copy writes no cleared flag).
#   * p37_add_copy(rec, info) registers a copy of a template - an encounter record p37_copy_record() made:
#     ids <template id>.<n> (its spawns' <entity id>.<n>), its centre at an anchor and every spawn point
#     moved and turned with it, persist_death false, no loot table - as an encounter of this director, so
#     activation, the budget and the formation cap, the leash, LOD, deactivation, the streaming rules
#     (P24b), formations (P30), stand-downs (P29) and crews (P32) all treat it as a placed one. Nothing of
#     a copy is saved: no kill, no cleared flag. info: {"xp_scale" (0..1), "patrol" (level-space points
#     its members walk in turn, each keeping its offset from the group's middle: a wanderer's road, a
#     raid's round of the houses), "owner" (who made it), "march" (true: a moving column - see p37_march)}.
#   * Each member a copy spawns gets its record's kill XP times the copy's xp_scale (the existing kill-XP
#     path reads the combatant's xp_reward: a template's fourth and later spawns pay none), its spawn's
#     `targets` (P30's provider for that unit: EnemyActor.p37_set_targets), the road points of its patrol,
#     and in a moving column the point it keeps to (EnemyActor.p37_join_march); its faction's standing
#     comes with its faction (EnemyActor's P11b: a neutral column walks past a giant at peace with it).
#   * p37_remove_copy(id) frees what is left of a copy (living members despawned, corpses freed, its
#     formations dissolved) and forgets it.
#   * p37_move_copy(id, centre, yaw) re-places a copy that is not in the world (an abstract column at its
#     path point): its centre, every spawn point (on the loaded ground's height when known) and the chunk
#     the streaming rules read. p37_march(id, centre, yaw) walks a copy in the world along its route: its
#     centre, and the pivot of each intact formation of it that is not engaged (aware of the giant): its
#     members follow their slots; its other members keep to points at their offsets from the centre.

## A copy's spawns and formations take these radii (the WanderDirector places a wanderer 120-220 m away).
const P37_ACTIVATE_M := 280.0
const P37_DEACTIVATE_M := 340.0
## A marching column's escorts make for their place this far ahead of the column (they walk faster).
const P37_ESCORT_LEAD_M := 6.0

## copy id -> info (see the notes): "xp_scale", "patrol", "owner", "march", "offsets" (entity id ->
## Vector3 offset from the centre at yaw 0), "yaw" (rad), "centre" (level space), "form_off" (formation
## id -> Vector3 pivot offset at yaw 0, captured when the formation first stands).
var _p37_copies := {}


func _p37_ready() -> void:
	if not member_spawned.is_connected(_p37_on_member_spawned):
		member_spawned.connect(_p37_on_member_spawned)


## True when `id` is a live copy of a template run by this director.
func p37_is_copy(id: String) -> bool:
	return _p37_copies.has(id) and _encounters.has(id)


## The ids of the live copies (sorted).
func p37_copy_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _p37_copies:
		if _encounters.has(id):
			out.append(id)
	out.sort()
	return out


## A copy's info ({} when it is no copy).
func p37_copy_info(id: String) -> Dictionary:
	return _p37_copies.get(id, {}) if _encounters.has(id) else {}


## A copy of template `tpl` (see the notes): id "<template id>.<n>", every spawn's entity id
## "<entity id>.<n>" (formation banners and engine crews renamed with them), the centre at `centre` (level
## space) and every spawn point and yaw (and every formation's yaw) moved and turned by `yaw` about the
## template's centre, each spawn's height from `ground` (Callable(pos: Vector3) -> float; NaN or none:
## the moved height), its `prefer` definition when that record exists, persist_death false, no loot, no
## flags of its own (the WanderDirector chose it), template false; `overrides` are merged last. The copy
## keeps its offsets in "_p37" ({"template", "n", "offsets", "yaws"}) for p37_move_copy.
static func p37_copy_record(tpl: Dictionary, n: int, centre: Vector3, yaw: float, ground: Callable = Callable(),
		overrides := {}) -> Dictionary:
	var rec := tpl.duplicate(true)
	var tpl_id := str(tpl.get("id", ""))
	var suffix := ".%d" % n
	var c0 := _vec3(tpl.get("center_m"))
	var basis := Basis(Vector3.UP, yaw)
	var offsets := {}
	var yaws := {}
	var renamed := {}
	for sp: Dictionary in rec.get("spawns", []):
		var old_id := str(sp.get("entity_id", ""))
		var new_id := old_id + suffix
		renamed[old_id] = new_id
		sp["entity_id"] = new_id
		var off := _vec3(sp.get("position_m")) - c0
		offsets[new_id] = off
		yaws[new_id] = float(sp.get("yaw_deg", 0.0))
		var at := centre + basis * off
		var h: float = float(ground.call(at)) if ground.is_valid() else NAN
		if not is_nan(h):
			at.y = h
		sp["position_m"] = [at.x, at.y, at.z]
		sp["yaw_deg"] = wrapf(float(sp.get("yaw_deg", 0.0)) + rad_to_deg(yaw), -180.0, 180.0)
		sp["persist_death"] = false
		sp["loot_table"] = ""
		var prefer := str(sp.get("prefer", ""))
		if prefer != "" and GameData.has_record(prefer):
			sp["definition"] = prefer
	var form_yaws := {}
	for f: Dictionary in rec.get("formations", []):
		if str(f.get("banner", "")) != "":
			f["banner"] = str(renamed.get(str(f.banner), str(f.banner) + suffix))
		if SchemaUtil.is_number(f.get("yaw_deg")):
			form_yaws[str(f.get("id", ""))] = float(f.yaw_deg)
			f["yaw_deg"] = wrapf(float(f.yaw_deg) + rad_to_deg(yaw), -180.0, 180.0)
	for e: Dictionary in rec.get("engines", []):
		var crew: Array = []
		for c: Variant in e.get("crew", []):
			crew.append(str(renamed.get(str(c), str(c) + suffix)))
		e["crew"] = crew
	rec["id"] = tpl_id + suffix
	rec["template"] = false
	rec["center_m"] = [centre.x, centre.y, centre.z]
	rec["requires_flags"] = []
	rec["forbids_flags"] = []
	rec["activate_radius_m"] = maxf(float(tpl.get("activate_radius_m", 0.0)), P37_ACTIVATE_M)
	rec["deactivate_radius_m"] = maxf(float(tpl.get("deactivate_radius_m", 0.0)), P37_DEACTIVATE_M)
	rec.merge(overrides, true)
	rec["_p37"] = {"template": tpl_id, "n": n, "offsets": offsets, "yaws": yaws, "form_yaws": form_yaws}
	return rec


## Registers a copy (a record from p37_copy_record) with its info (see the notes); it activates at the next
## update when the giant is within its activate radius and its chunk is ready. False when the id is taken.
func p37_add_copy(rec: Dictionary, info := {}) -> bool:
	var id := str(rec.get("id", ""))
	if id == "" or _encounters.has(id) or level == null:
		return false
	for s: Variant in rec.get("spawns", []):
		if typeof(s) == TYPE_DICTIONARY and _members.has(str(s.get("entity_id", ""))):
			return false   # a member id still in use (the counter of its maker restarted)
	var origin := level.global_transform if level.is_inside_tree() else level.transform
	var enc := Encounter.new()
	enc.id = id
	enc.record = rec
	enc.flag = cleared_flag(id)
	enc.center = origin * _vec3(rec.get("center_m"))
	enc.activate_r = float(rec.get("activate_radius_m", P37_ACTIVATE_M))
	enc.deactivate_r = float(rec.get("deactivate_radius_m", P37_DEACTIVATE_M))
	enc.leash_r = float(rec.get("leash_radius_m", 0.0))
	enc.alert_group = bool(rec.get("alert_group", true))
	enc.counts_budget = bool(rec.get("counts_toward_budget", true))
	for s: Variant in rec.get("spawns", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var m := Member.new()
		m.entity_id = str(s.get("entity_id", ""))
		m.encounter_id = id
		m.spawn = s
		m.definition = str(s.get("definition", ""))
		var def := GameData.get_record(m.definition)
		m.enemy_def = str(def.get("type", "")) == "enemy"
		m.budgeted = enc.counts_budget and m.enemy_def
		m.faction = str(s.get("faction", ""))
		if m.entity_id == "":
			continue
		_members[m.entity_id] = m
		enc.members.append(m)
		_scene(str(def.get("scene", "")))   # the spawn hitch: the scene is cached before it is needed
	var meta: Dictionary = rec.get("_p37", {})
	var stored := info.duplicate()
	stored["offsets"] = meta.get("offsets", {})
	stored["yaws"] = meta.get("yaws", {})
	stored["form_yaws"] = meta.get("form_yaws", {})
	var mean := Vector3.ZERO
	for o: Vector3 in (stored.offsets as Dictionary).values():
		mean += o
	stored["group_off"] = mean / float(maxi(1, (stored.offsets as Dictionary).size()))
	stored["centre"] = _vec3(rec.get("center_m"))
	stored["yaw"] = float(info.get("yaw", 0.0))
	stored["form_off"] = {}
	_p37_copies[id] = stored
	_encounters[id] = enc
	_order.append(id)
	_order.sort()
	_dirty = true
	return true


## Frees what is left of a copy and forgets it (see the notes). Call it from a safe point (a Sim hook).
func p37_remove_copy(id: String) -> void:
	var enc: Encounter = _encounters.get(id)
	_p37_copies.erase(id)
	if enc == null:
		return
	_p30_dissolve_encounter(id)
	for m: Member in enc.members:
		if m.node != null and is_instance_valid(m.node):
			if "ai_enabled" in m.node:
				m.node.set("ai_enabled", false)
			_free_node(m.node)
		m.node = null
		_members.erase(m.entity_id)
		_p24b_skipped.erase(m.entity_id)
	_encounters.erase(id)
	var i := _order.find(id)
	if i >= 0:
		_order.remove_at(i)
	_p24b_chunks.erase(id)
	_p29_down.erase(id)


## Living, spawned members of a copy (or of any encounter).
func p37_living(id: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var enc: Encounter = _encounters.get(id)
	if enc == null:
		return out
	for m: Member in enc.members:
		if m.status == SPAWNED and _alive(m.node):
			out.append(m.node)
	return out


## True when no member of the encounter is left to fight: each is dead, routed, or (sitting this
## activation out) skipped - its encounter cleared, or about to be (members that never spawned count
## as standing).
func p37_defeated(id: String) -> bool:
	var enc: Encounter = _encounters.get(id)
	if enc == null:
		return false
	if enc.state == CLEARED:
		return true
	for m: Member in enc.members:
		if m.status == DEAD or _p24b_skipped.has(m.entity_id):
			continue
		if m.status == SPAWNED and m.routed:
			continue
		return false
	return not enc.members.is_empty()


## True while a member of the encounter is aware of the giant (and not walking home).
func p37_engaged(id: String) -> bool:
	var enc: Encounter = _encounters.get(id)
	return enc != null and enc.state == ACTIVE and _any_aware(enc)


## Re-places a copy that is not in the world: its centre (level space) and yaw, every spawn point at its
## offset (turned by yaw; on the loaded ground's height through `ground` when known), and the chunk the
## streaming rules read. A copy in the world keeps its members where they are (use p37_march).
func p37_move_copy(id: String, centre: Vector3, yaw: float, ground: Callable = Callable()) -> void:
	var enc: Encounter = _encounters.get(id)
	var info: Dictionary = _p37_copies.get(id, {})
	if enc == null or info.is_empty():
		return
	var origin := level.global_transform if level != null and level.is_inside_tree() else Transform3D.IDENTITY
	info["centre"] = centre
	info["yaw"] = yaw
	enc.center = origin * centre
	(enc.record as Dictionary)["center_m"] = [centre.x, centre.y, centre.z]
	_p24b_chunks.erase(id)
	var form_yaws: Dictionary = info.get("form_yaws", {})
	for f: Dictionary in enc.record.get("formations", []):
		if form_yaws.has(str(f.get("id", ""))):
			f["yaw_deg"] = wrapf(float(form_yaws[str(f.id)]) + rad_to_deg(yaw), -180.0, 180.0)
	var basis := Basis(Vector3.UP, yaw)
	var offsets: Dictionary = info.get("offsets", {})
	var yaws: Dictionary = info.get("yaws", {})
	for m: Member in enc.members:
		if m.status == SPAWNED:
			continue
		var at := centre + basis * (offsets.get(m.entity_id, Vector3.ZERO) as Vector3)
		var h: float = float(ground.call(at)) if ground.is_valid() else NAN
		if not is_nan(h):
			at.y = h
		m.spawn["position_m"] = [at.x, at.y, at.z]
		m.spawn["yaw_deg"] = wrapf(float(yaws.get(m.entity_id, 0.0)) + rad_to_deg(yaw), -180.0, 180.0)
	_dirty = true   # its activation is looked at again on the next tick (it may have walked onto loaded ground)


## Walks a copy in the world along its route (see the notes): its centre to `centre` (level space) facing
## `yaw`, the pivot of every intact formation of it not engaged with the giant (its offset from the centre
## kept), and the points its other members keep to. Returns true when no formation of it was engaged.
func p37_march(id: String, centre: Vector3, yaw: float) -> bool:
	var enc: Encounter = _encounters.get(id)
	var info: Dictionary = _p37_copies.get(id, {})
	if enc == null or info.is_empty():
		return false
	var origin := level.global_transform if level != null and level.is_inside_tree() else Transform3D.IDENTITY
	var free := true
	var form_off: Dictionary = info.get("form_off", {})
	var basis := Basis(Vector3.UP, yaw)
	for fid: String in _p30_by_encounter.get(id, PackedStringArray()):
		var f: Formation = _p30_formations.get(fid)
		if f == null or f.dissolved:
			continue
		if not form_off.has(fid):
			var c0 := origin * (info.get("centre", centre) as Vector3)
			form_off[fid] = Basis(Vector3.UP, -float(info.get("yaw", yaw))) * (f.pivot - c0)
		if not f.is_intact():
			continue
		if f.aware or f.state != "formed":
			free = false
			continue
		var p := origin * (centre + basis * (form_off[fid] as Vector3))
		f.pivot = Vector3(p.x, f.pivot.y, p.z)
		f.home_pivot = f.pivot
		f.facing_yaw = wrapf(yaw, -PI, PI)
		f.home_yaw = f.facing_yaw
	info["form_off"] = form_off
	info["centre"] = centre
	info["yaw"] = yaw
	enc.center = origin * centre
	(enc.record as Dictionary)["center_m"] = [centre.x, centre.y, centre.z]
	_p24b_chunks.erase(id)
	# Its members in no formation (escorts: the column's riders), hostile and walking: the patrol point
	# they make for is their place a little ahead of the column (at peace, EnemyActor.p37_join_march's
	# post does it).
	var ahead := Formation.forward_of(yaw) * P37_ESCORT_LEAD_M
	for m: Member in enc.members:
		if m.status != SPAWNED or not _alive(m.node) or m.node.get("formation") != null:
			continue
		var b := m.node.get("brain") as EnemyBrain
		if b == null or b.at_peace() or b.aware:
			continue
		var t := p37_march_target(id, m.entity_id)
		if not t.is_empty():
			var pts: Array[Vector3] = [(t.point as Vector3) + ahead]
			b.patrol_points = pts
	return free and not _any_aware(enc)


## Where a member of a moving copy keeps to now: {"point" (global; its formation slot while its formation
## stands, else its offset from the copy's centre), "yaw" (the column's heading)}; {} when it is none.
func p37_march_target(id: String, entity_id: String) -> Dictionary:
	var info: Dictionary = _p37_copies.get(id, {})
	if info.is_empty() or not bool(info.get("march", false)):
		return {}
	var origin := level.global_transform if level != null and level.is_inside_tree() else Transform3D.IDENTITY
	var yaw := float(info.get("yaw", 0.0))
	var off: Vector3 = (info.get("offsets", {}) as Dictionary).get(entity_id, Vector3.ZERO)
	var p := origin * ((info.get("centre", Vector3.ZERO) as Vector3) + Basis(Vector3.UP, yaw) * off)
	return {"point": p, "yaw": yaw}


## Deactivates a copy now (an abstract column whose point left the loaded ground): its living members
## are freed and come back at their spawn points on its next activation.
func p37_deactivate(id: String) -> void:
	var enc: Encounter = _encounters.get(id)
	if enc != null and enc.state == ACTIVE:
		_deactivate(enc)


func _p37_on_member_spawned(encounter_id: String, entity_id: String, node: Node3D) -> void:
	var info: Dictionary = _p37_copies.get(encounter_id, {})
	var m: Member = _members.get(entity_id)
	if info.is_empty() or m == null or node == null or not is_instance_valid(node):
		return
	var e: Variant = node.get("entity")
	if e is CombatEntity and (e as CombatEntity).combatant != null:
		var base := int(GameData.get_record(m.definition).get("xp_reward", 0))
		(e as CombatEntity).combatant.xp_reward = int(roundf(float(base) * clampf(float(info.get("xp_scale", 1.0)), 0.0, 1.0)))
	if typeof(m.spawn.get("targets")) == TYPE_DICTIONARY and node.has_method("p37_set_targets"):
		node.call("p37_set_targets", m.spawn.targets)
	var brain: Variant = node.get("brain")
	var patrol: Array = info.get("patrol", [])
	if not patrol.is_empty() and brain is EnemyBrain:
		var off: Vector3 = (info.get("offsets", {}) as Dictionary).get(entity_id, Vector3.ZERO) - (info.get("group_off", Vector3.ZERO) as Vector3)
		var basis := Basis(Vector3.UP, float(info.get("yaw", 0.0)))
		var origin := level.global_transform if level != null and level.is_inside_tree() else Transform3D.IDENTITY
		var points: Array[Vector3] = []
		for p: Vector3 in patrol:
			points.append(origin * (p + basis * Vector3(off.x, 0.0, off.z)))
		(brain as EnemyBrain).patrol_points = points
	if bool(info.get("march", false)) and node.has_method("p37_join_march"):
		var copy_id := encounter_id
		node.call("p37_join_march", func() -> Dictionary: return p37_march_target(copy_id, entity_id))


## Loads the scenes the templates `template_ids` spawn (their definitions, and the records they prefer
## when those exist) into the shared cache at level load, so no copy loads a scene when it appears (the
## spawn hitch, P17a). Returns how many it loaded now.
func p37_preload(template_ids: PackedStringArray) -> int:
	var loaded := 0
	for tid in template_ids:
		for s: Variant in GameData.get_record(tid).get("spawns", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var defs := [str(s.get("definition", ""))]
			if str(s.get("prefer", "")) != "" and GameData.has_record(str(s.prefer)):
				defs.append(str(s.prefer))
			for d: String in defs:
				var path := str(GameData.get_record(d).get("scene", ""))
				if path != "" and not _scene_cache.has(path):
					_scene(path)
					loaded += 1
	return loaded
