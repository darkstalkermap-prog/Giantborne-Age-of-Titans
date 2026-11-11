class_name WanderDirector
extends Node
## The living world (P37; plan M6-M9 §2.13, §5.10, decision 27): the runtime node "WanderDirector" that
## LevelRoot.RUNTIME_NODES makes in level.world (group wander_director). The world moves without the
## player - patrols, packs, raiders and columns on the roads, raids on its settlements - but never on
## ground that is not loaded, and nothing it does can be farmed. It runs in the campaign only (like
## Quests: a test turns it on with test_active), from a Sim PRE_ACTORS hook after the EncounterDirector.
##
## Wandering encounters (`wander_table` records, one per region): while the giant stands in a table's
## region, every interval_s (a random span; RETRY_S after an attempt that found no place) it may add one
## copy of a template, chosen by weight among the entries whose stage range holds the giant's stage, whose
## requires_flags are truthy and forbids_flags not and whose conditions hold - which is how faction
## standings filter them (Brannock's militia while the town is hostile, Aldmere's cavalry while the
## kingdom is). At most max_active copies of a table live at once, and only when the director's budget
## has room for its combatants and the formation cap for its formation members. The copy stands at an
## anchor (anchors "roads": a road node of the region; "markers", "pois": the region's markers or places)
## min_distance_m..max_distance_m from the giant (on the ground plane), outside the camera's view (every
## spawn point outside its frustum), with every spawn point on loaded, ready ground and the anchor on the
## human navmesh (one query of NavQuery's per-tick budget), never inside a settlement, never within
## ENCOUNTER_GAP_M of a placed encounter that is not cleared, COPY_GAP_M of another copy or EVENT_CLEAR_M
## of a running world event. It faces along the road and its members walk the road's nodes within the
## table's patrol_m of the anchor. An entry with a `route` (or a `path`) is a moving column: it is placed
## on its route and marches along it (see the columns below), leaving the world at its end. Each spawn
## counts in the flag wander.<table short>.<entry>.spawns; a template's members pay their kill XP for the
## first xp_full_spawns (3) spawns of an entry only. A copy leaves the world when the giant leaves it
## (its encounter deactivates), when it is cleared (once its corpses are gone) and, never reached, after
## STALE_S; nothing of it is saved.
##
## World events (`world_event` records of the level; WorldEvent holds a run's state and pure rules): at
## most one runs at a time; one may start when WorldEvent.can_start_with holds - its trigger, its
## cooldown, its centre chunk loaded and ready and the giant within start_radius_m (200) of the centre.
## While it runs it is in the tracker, the compass, the map and the journal (Quests' P37 section) and a
## respawn within EVENT_CLEAR_M (120) of it moves to another checkpoint (GameSession's respawn blockers;
## fast travel there is refused the same way). See world_event.gd for its rules: suspension while its
## centre chunk is unloaded, the protect objective, the fail rule, outcomes, the death reset.
##
## Moving columns (a route: the road graph of the level's world index from one place to another, there
## and back when round_trip): the column's point walks at speed_mps as a path parameter whatever is
## loaded, standing still while a member of it is engaged with the giant. Its copy is in the world only
## while that point lies on loaded, ready ground within the copy's activate radius of the giant (the
## director activates it there); when the point leaves loaded ground it is despawned back into the
## abstract (p37_deactivate) and comes back further along. In the world its formations' pivots walk
## with the point (EncounterDirector.p37_march) and its members keep to their places (EnemyActor.
## p37_join_march), a neutral column walking past a giant at peace with its faction.
##
## State across reloads: a running event is carried in a static table (by level) so that a death reload
## restarts its attempt (and moves the respawn away from it) and a travel resumes it; the title, a new
## game or a continue forget it (Events.mode_change_requested).

const GROUP := "wander_director"
## PRE_ACTORS, after the EncounterDirector (10): a copy added here activates at the director's next update.
const HOOK_ORDER := 12
## Tables and triggers are checked this often; running events and columns are updated this often.
const CHECK_TICKS := 30
const UPDATE_TICKS := 6
## An attempt that found no entry or no place is tried again this soon.
const RETRY_S := 10.0
## Wanderers keep out of settlements (their radius plus this), away from placed encounters that are not
## cleared, from other copies and from running events.
const SETTLEMENT_MARGIN_M := 25.0
const ENCOUNTER_GAP_M := 90.0
const COPY_GAP_M := 120.0
const EVENT_CLEAR_M := 120.0
## A wanderer's anchor must lie this close to the human navmesh.
const NAV_SNAP_M := 4.0
const NAV_LAYER := 1
const DEFAULT_PATROL_M := 40.0
const DEFAULT_INTERVAL_S := [60.0, 120.0]
const DEFAULT_MIN_M := 120.0
const DEFAULT_MAX_M := 220.0
const DEFAULT_XP_FULL_SPAWNS := 3
## A copy the giant never came near is dropped after this long; a cleared one after its corpses.
const STALE_S := 90.0
const CLEARED_LINGER_S := 8.0
## A moving entry's places are sampled along its route this far apart.
const ROUTE_SAMPLE_M := 12.0
## The text of a respawn refused near a running event that names none.
const RESPAWN_TEXT := "%s still rages there."
const ABANDONED := "abandoned"

## Tests: run outside the campaign (as Quests.test_active).
static var test_active := false
## Tests: Callable(pos: Vector3) -> bool saying whether a point is in the camera's view (unset: the
## viewport's camera frustum).
static var view_probe := Callable()
## level id -> {event id -> {"runs", "last_start_s", "centre": Vector3, "s", "reset": bool}}: the events
## running when their level was left (a death, a travel), carried to its next load.
static var _carry := {}

var level: LevelRoot = null
var director: EncounterDirector = null
## region id -> wander table record (of this level's regions).
var tables := {}
## event id -> WorldEvent (this level's).
var events := {}
## Every spawn, in order: {"tick", "table", "entry", "copy", "template", "anchor", "xp_scale"} (tests,
## metrics).
var spawn_log: Array = []
## Why the last attempts of each table found nothing: reason -> count (tests, debug).
var refusals := {}

var _table_state := {}     # table id -> {"next_tick": int}
var _copies := {}          # copy id -> {"table", "entry", "template", "route": Route or null, "made_tick",
							#  "active_seen": bool, "cleared_tick": int}
var _counter := 0
var _roads := {}           # region id -> PackedInt32Array of road node indices in it
var _adjacent := {}        # road node index -> [[neighbour, length], ...]
var _dead := {}            # entity ids seen dying in this load (an event's people targets)
var _removals := PackedStringArray()   # copies to remove at the next tick (from signal handlers)


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group("debug_info_providers")


func _ready() -> void:
	level = _find_level()
	director = level.director() if level != null else null
	refresh()
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, _on_tick, HOOK_ORDER)
	if not Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.connect(_on_entity_died)
	if not Events.mode_change_requested.is_connected(_on_mode_change_requested):
		Events.mode_change_requested.connect(_on_mode_change_requested)
	GameSession.register_respawn_blocker(_respawn_blocker)
	if director != null and not director.member_spawned.is_connected(_on_member_spawned):
		director.member_spawned.connect(_on_member_spawned)
	_resume_carried()


func _exit_tree() -> void:
	Sim.remove_hooks(self)
	if Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.disconnect(_on_entity_died)
	if Events.mode_change_requested.is_connected(_on_mode_change_requested):
		Events.mode_change_requested.disconnect(_on_mode_change_requested)
	GameSession.unregister_respawn_blocker(_respawn_blocker)
	for e: WorldEvent in events.values():
		if e.is_running() and Quests.has_method("p37_clear_event"):
			Quests.p37_clear_event(e.id)


## Re-reads this level's wander tables and world events and the road graph (tests installing records).
func refresh() -> void:
	tables.clear()
	events.clear()
	if level == null:
		return
	var templates := PackedStringArray()
	for rec: Dictionary in GameData.records_of_type("wander_table"):
		var region := GameData.get_record(str(rec.get("region", "")))
		if str(region.get("level", "")) != level.level_id:
			continue
		tables[str(rec.region)] = rec
		for entry: Dictionary in rec.get("entries", []):
			templates.append(str(entry.get("template", "")))
		if not _table_state.has(str(rec.id)):
			_table_state[str(rec.id)] = {"next_tick": Sim.tick + seconds_to_ticks(_interval(rec))}
	for rec: Dictionary in GameData.records_of_type("world_event"):
		if str(rec.get("level", "")) != level.level_id:
			continue
		events[str(rec.id)] = WorldEvent.make(rec)
		for t: Variant in rec.get("encounters", []):
			templates.append(str(t))
	if director != null:
		director.p37_preload(templates)
	_build_roads()


## True while the living world runs: in the campaign, or in a test that turned it on.
static func is_live() -> bool:
	return test_active or GameSession.is_campaign()


## The clock of cooldowns: the campaign's play time (saved with every checkpoint), else Sim's (tests).
static func clock_s() -> float:
	if GameSession.is_campaign():
		return float(GameSession.stats.get("play_time_s", 0.0))
	return float(Sim.tick) * Sim.DT


static func seconds_to_ticks(s: float) -> int:
	return maxi(1, int(roundf(s * float(Sim.TICK_RATE))))


## Tests: forget everything static (the carried events, the test switches).
static func reset_for_tests() -> void:
	test_active = false
	view_probe = Callable()
	_carry.clear()


# --------------------------------------------------------------------------- the tick

func _on_tick(tick: int) -> void:
	if not is_inside_tree() or level == null or director == null or not is_live():
		return
	for id in _removals:
		_remove_copy(id)
	_removals.clear()
	if tick % UPDATE_TICKS == 0:
		var dt := float(UPDATE_TICKS) * Sim.DT
		_update_columns(dt)
		for eid: String in _event_ids():
			var e: WorldEvent = events[eid]
			if e.is_running():
				update_event(e, dt, tick)
	if tick % CHECK_TICKS == 0:
		_prune_copies(tick)
		check_events(tick)
		check_tables(tick)


func _event_ids() -> PackedStringArray:
	var ids := PackedStringArray(events.keys())
	ids.sort()
	return ids


# --------------------------------------------------------------------------- wandering encounters

## The table of the region the giant stands in, if its time has come: one attempt to add a copy.
func check_tables(tick: int) -> void:
	var p := _player()
	if p == null:
		return
	var table: Dictionary = tables.get(_region_at(p.global_position), {})
	if table.is_empty():
		return
	var st: Dictionary = _table_state.get(str(table.id), {})
	if st.is_empty():
		st = {"next_tick": tick}
		_table_state[str(table.id)] = st
	if tick < int(st.next_tick):
		return
	var r := try_spawn(table, tick)
	st.next_tick = tick + seconds_to_ticks(_interval(table) if bool(r.get("ok", false)) else RETRY_S)


## One attempt of `table` to add a wanderer now: {"ok", "copy", "entry", "reason"}. The reasons (counted
## in refusals): no_player, cap (max_active), no_entry, budget, no_place, add_failed.
func try_spawn(table: Dictionary, tick: int = Sim.tick, entry_id := "") -> Dictionary:
	var p := _player()
	if p == null:
		return _refuse("no_player")
	if live_copies_of(str(table.id)).size() >= int(table.get("max_active", 2)):
		return _refuse("cap")
	var entries := eligible_entries(table, p.current_growth_stage(), Quests.condition_context())
	if entry_id != "":
		entries = entries.filter(func(e: Dictionary) -> bool: return str(e.id) == entry_id)
	var entry := pick_entry(entries, Sim.rng_for("wander"))
	if entry.is_empty():
		return _refuse("no_entry")
	var tpl := GameData.get_record(str(entry.template))
	if not budget_allows(tpl):
		return _refuse("budget")
	var place := find_place(table, entry, tpl, p.global_position)
	if place.is_empty():
		return _refuse("no_place")
	var key := spawns_flag(str(table.id), str(entry.id))
	var count := int(WorldState.get_flag(key, 0)) + 1 if SchemaUtil.is_number(WorldState.get_flag(key, 0)) else 1
	var scale := xp_scale_for(count, int(table.get("xp_full_spawns", DEFAULT_XP_FULL_SPAWNS)))
	_counter += 1
	var rec := EncounterDirector.p37_copy_record(tpl, _counter, place.anchor, float(place.yaw), _ground_fn())
	var info := {"owner": "wander", "table": str(table.id), "entry": str(entry.id), "xp_scale": scale,
		"yaw": float(place.yaw), "patrol": place.get("patrol", []), "march": place.get("route") != null}
	if not director.p37_add_copy(rec, info):
		return _refuse("add_failed")
	WorldState.set_flag(key, count)
	var id := str(rec.id)
	_copies[id] = {"table": str(table.id), "entry": str(entry.id), "template": str(tpl.id), "route": place.get("route"),
		"made_tick": tick, "active_seen": false, "cleared_tick": -1}
	spawn_log.append({"tick": tick, "table": str(table.id), "entry": str(entry.id), "copy": id, "template": str(tpl.id),
		"anchor": place.anchor, "xp_scale": scale})
	Events.wander_spawned.emit(tick, str(tpl.id), id)
	return {"ok": true, "copy": id, "entry": str(entry.id), "reason": ""}


func _refuse(reason: String) -> Dictionary:
	refusals[reason] = int(refusals.get(reason, 0)) + 1
	return {"ok": false, "copy": "", "entry": "", "reason": reason}


## The flag counting an entry's spawns: wander.<table short>.<entry>.spawns.
static func spawns_flag(table_id: String, entry_id: String) -> String:
	return "wander.%s.%s.spawns" % [table_id.trim_prefix("wander."), entry_id]


## The kill-XP share of an entry's `count`-th spawn: 1 for its first `full` spawns, then 0. Pure.
static func xp_scale_for(count: int, full: int) -> float:
	return 1.0 if count <= full else 0.0


## The entries of `table` a giant of `stage` may meet now: its stage range, flags (truthy / not) and
## conditions (quest conditions in `ctx`). Pure but for ctx.
static func eligible_entries(table: Dictionary, stage: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var flags: Dictionary = ctx.get("flags", {})
	for e: Variant in table.get("entries", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if SchemaUtil.is_number(e.get("min_stage")) and stage < int(e.min_stage):
			continue
		if SchemaUtil.is_number(e.get("max_stage")) and stage > int(e.max_stage):
			continue
		var ok := true
		for f: Variant in e.get("requires_flags", []):
			ok = ok and QuestConditions.truthy(flags.get(str(f)))
		for f: Variant in e.get("forbids_flags", []):
			ok = ok and not QuestConditions.truthy(flags.get(str(f)))
		if ok and typeof(e.get("conditions")) == TYPE_ARRAY:
			ok = QuestConditions.all_hold(e.conditions, ctx)
		if ok:
			out.append(e)
	return out


## One of `entries` by weight (rng's draw); {} when there is none. Pure but for rng.
static func pick_entry(entries: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for e: Dictionary in entries:
		total += maxf(0.0, float(e.get("weight", 1.0)))
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for e: Dictionary in entries:
		roll -= maxf(0.0, float(e.get("weight", 1.0)))
		if roll < 0.0:
			return e
	return entries[entries.size() - 1]


## True when the director has room for every combatant and formation member of `tpl` now (copies spawn
## whole or not at all, never one member at a time as room frees up).
func budget_allows(tpl: Dictionary) -> bool:
	var budgeted := 0
	var formation := 0
	var counts_budget := bool(tpl.get("counts_toward_budget", true))
	for s: Variant in tpl.get("spawns", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var def := GameData.get_record(str(s.get("definition", "")))
		if str(def.get("type", "")) != "enemy":
			continue
		if str(s.get("formation", "")) != "":
			formation += 1
		elif counts_budget or (str(s.get("faction", "")) != "" and FactionState.is_hostile(str(s.faction))):
			budgeted += 1
	if budgeted > 0 and director.active_combatant_count() + budgeted > director.max_active_enemies:
		return false
	if formation > 0:
		director.p30_formation_room()   # loads the level's cap
		if director.formation_member_count() + formation > director.max_formation_members:
			return false
	return true


## Where a copy of `tpl` for `entry` of `table` may stand now, the giant at `from`: {"anchor" (level
## space), "yaw", "patrol" (road points), "route" (a Route for a moving entry, its walk set to the place)}
## or {} when nowhere fits (see the class notes). Tries the candidates in a random order (the wander RNG).
func find_place(table: Dictionary, entry: Dictionary, tpl: Dictionary, from: Vector3) -> Dictionary:
	var lo := float(table.get("min_distance_m", DEFAULT_MIN_M))
	var hi := float(table.get("max_distance_m", DEFAULT_MAX_M))
	var region := str(table.get("region", ""))
	var candidates: Array = []   # [anchor, yaw, extra]
	var route := build_route(entry, float(entry.get("speed_mps", WorldEvent.DEFAULT_SPEED_MPS)))
	if route != null:
		var t := 0.0
		while t <= route.length:
			var at := route.point_at(t)
			if _region_at(at) == region:
				candidates.append([at, route.yaw_at(t), t])
			t += ROUTE_SAMPLE_M
	else:
		match str(table.get("anchors", "roads")):
			"roads":
				var nodes := _index().road_nodes() if _index() != null else PackedVector3Array()
				for i: int in _roads.get(region, PackedInt32Array()):
					candidates.append([nodes[i], _road_yaw(i), i])
			"markers":
				for id: String in _index_ids("markers"):
					var at := _index().position_of(id)
					if _region_at(at) == region:
						candidates.append([at, 0.0, -1])
			"pois":
				for id: String in _index_ids("pois"):
					var at := _index().position_of(id)
					if _region_at(at) == region and str((_index().pois[id] as Dictionary).get("kind", "")) != "settlement":
						candidates.append([at, 0.0, -1])
	var near: Array = []
	for c: Array in candidates:
		var d := _flat(c[0] - from)
		if d >= lo and d <= hi:
			near.append(c)
	_shuffle(near, Sim.rng_for("wander"))
	var probes := 0
	for c: Array in near:
		var anchor: Vector3 = c[0]
		if not _clear_of_others(anchor):
			continue
		var yaw: float = c[1]
		var points := footprint(tpl, anchor, yaw)
		if not _ground_ready(points) or _any_in_view(points):
			continue
		var snapped := _snap(anchor)
		probes += 1
		if not snapped.is_finite():
			if probes >= 4:
				break   # the tick's path-query budget is not ours to spend: try again later
			continue
		var h := _height(anchor)
		if not is_nan(h):
			anchor.y = h
		var out := {"anchor": anchor, "yaw": yaw}
		if route != null:
			route.s = float(c[2])
			out["route"] = route
		else:
			out["patrol"] = patrol_points(int(c[2]), float(table.get("patrol_m", DEFAULT_PATROL_M)), anchor)
		return out
	return {}


## Where `tpl`'s spawns stand with its centre at `anchor`, turned by `yaw` (level space, template height).
static func footprint(tpl: Dictionary, anchor: Vector3, yaw: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c0 := WorldEvent._vec3(tpl.get("center_m"))
	var basis := Basis(Vector3.UP, yaw)
	for s: Variant in tpl.get("spawns", []):
		if typeof(s) == TYPE_DICTIONARY:
			out.append(anchor + basis * (WorldEvent._vec3(s.get("position_m")) - c0))
	return out


## The road points a wanderer at road node `node` walks: the nodes reachable along the road within
## `reach_m` either way, as a there-and-back list through the anchor ([] for no node or no reach).
func patrol_points(node: int, reach_m: float, anchor: Vector3) -> Array:
	if node < 0 or reach_m <= 0.0 or _index() == null:
		return []
	var nodes := _index().road_nodes()
	var ends: Array = []
	for pair: Array in _adjacent.get(node, []):
		var prev := node
		var cur: int = pair[0]
		var walked: float = pair[1]
		while walked < reach_m:
			var nxt := -1
			for q: Array in _adjacent.get(cur, []):
				if int(q[0]) != prev:
					nxt = int(q[0])
					walked += float(q[1])
					break
			if nxt < 0 or walked > reach_m:
				break
			prev = cur
			cur = nxt
		ends.append(nodes[cur])
	if ends.is_empty():
		return []
	var out: Array = []
	for e: Vector3 in ends:
		out.append(e)
		out.append(anchor)
	return out


## The live copies of a wander table.
func live_copies_of(table_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _copies:
		if str(_copies[id].table) == table_id and director.encounter_state(id) != "":
			out.append(id)
	out.sort()
	return out


## Every live copy this node made (wanderers and events' encounters), sorted.
func copy_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _copies:
		if director != null and director.encounter_state(id) != "":
			out.append(id)
	for e: WorldEvent in events.values():
		for id in e.copies:
			if director != null and director.encounter_state(id) != "" and not out.has(id):
				out.append(id)
	out.sort()
	return out


## A member came into the world: a copy's means the giant has reached that copy; a villager of the folk a
## running event hunts, near its centre, comes out into the raid and runs for shelter.
func _on_member_spawned(encounter_id: String, _entity_id: String, node: Node3D) -> void:
	if _copies.has(encounter_id):
		(_copies[encounter_id] as Dictionary)["active_seen"] = true
	var e := running_event()
	var c := node as Civilian
	if e != null and e.state == WorldEvent.RUNNING and c != null and c.brain != null \
			and _hunted_factions(e).has(c.faction) and _flat(c.global_position - _to_global(e.centre)) <= WorldEvent.SHELTER_RADIUS_M:
		c.brain.on_noise(Sim.tick, 0.0)


## Drops wanderers the giant left behind, cleared ones once their dead are gone, and ones never reached.
func _prune_copies(tick: int) -> void:
	for id: String in _copies.keys():
		var c: Dictionary = _copies[id]
		var state := director.encounter_state(id)
		if state == "":
			_copies.erase(id)
			continue
		if state == EncounterDirector.ACTIVE:
			c.active_seen = true
		if state == EncounterDirector.CLEARED:
			if int(c.cleared_tick) < 0:
				c.cleared_tick = tick
			if tick - int(c.cleared_tick) >= seconds_to_ticks(director.corpse_free_s + CLEARED_LINGER_S):
				_remove_copy(id)
			continue
		if state == EncounterDirector.DORMANT and bool(c.active_seen):
			_remove_copy(id)   # the giant left it: wanderers move on
		elif state == EncounterDirector.DORMANT and tick - int(c.made_tick) >= seconds_to_ticks(STALE_S):
			_remove_copy(id)


## Removes a copy now (its living members and corpses go; tests and the bot).
func drop_copy(id: String) -> void:
	_remove_copy(id)


func _remove_copy(id: String) -> void:
	_copies.erase(id)
	if director != null:
		director.p37_remove_copy(id)


# --------------------------------------------------------------------------- moving columns

## A Route for an entry or event record with a `route` ({from, to, round_trip, stage}: the road graph of
## the level's index between those places) or a `path` (a patrol route of the level); null without one,
## or when the places or the road are unknown.
func build_route(rec: Dictionary, speed := WorldEvent.DEFAULT_SPEED_MPS) -> WorldEvent.Route:
	var pts := PackedVector3Array()
	var round_trip := false
	if typeof(rec.get("route")) == TYPE_DICTIONARY:
		var r: Dictionary = rec.route
		round_trip = bool(r.get("round_trip", false))
		var idx := _index()
		if idx == null:
			return null
		var a := idx.position_of(str(r.get("from", "")))
		var b := idx.position_of(str(r.get("to", "")))
		if not a.is_finite() or not b.is_finite():
			return null
		pts = idx.route(a, b, int(r.get("stage", 3)))
	elif str(rec.get("path", "")) != "" and level != null:
		var node := level.patrol_route(str(rec.path))
		if node != null:
			for ch in node.get_children():
				if ch is Node3D:
					pts.append((ch as Node3D).global_position)
	if pts.size() < 2:
		return null
	var route := WorldEvent.Route.from_points(pts, round_trip, speed)
	return route if route.is_valid() else null


## A moving event's route, its walk begun where the event's centre lies on it (its column forms up there;
## a round trip comes back there); null for an event that does not move.
func _event_route(e: WorldEvent) -> WorldEvent.Route:
	if not e.is_moving():
		return null
	var r := build_route(e.record, float(e.record.get("speed_mps", WorldEvent.DEFAULT_SPEED_MPS)))
	if r != null:
		r.begin_at(r.project(e.centre))
	return r


## Walks every moving wanderer one update along its route. At its route's end it leaves the world - at
## once out of the giant's view, else it stands there until the giant leaves it (no one vanishes in view).
func _update_columns(dt: float) -> void:
	for id: String in _copies.keys():
		var c: Dictionary = _copies[id]
		if c.route == null:
			continue
		if march(id, c.route, dt) == "done":
			if copy_in_view(id):
				c.route = null
				c.active_seen = true
			else:
				_remove_copy(id)


## One update of the column `copy_id` on `route`: its point walks on unless a member is engaged; in the
## world it walks its formations along (or is despawned back into the abstract when its point left the
## loaded ground); out of it, its spawn points follow the point. Returns "done" at the route's end.
func march(copy_id: String, route: WorldEvent.Route, dt: float) -> String:
	var state := director.encounter_state(copy_id)
	if state == "" or state == EncounterDirector.CLEARED:
		return "done" if route.done() else ""
	if not director.p37_engaged(copy_id):
		route.advance(dt)
	var p := route.point_at()
	var h := _height(p)
	if not is_nan(h):
		p.y = h
	var yaw := route.yaw_at()
	if state == EncounterDirector.ACTIVE:
		if not _ready_at(p):
			director.p37_deactivate(copy_id)
		else:
			director.p37_march(copy_id, p, yaw)
	else:
		director.p37_move_copy(copy_id, p, yaw, _ground_fn())
	return "done" if route.done() else ""


# --------------------------------------------------------------------------- world events

## The event that runs now (null when none).
func running_event() -> WorldEvent:
	for eid: String in _event_ids():
		var e: WorldEvent = events[eid]
		if e.is_running():
			return e
	return null


## Starts the first event (by id) whose rules hold, when none runs.
func check_events(tick: int) -> void:
	if running_event() != null or _player() == null:
		return
	for eid: String in _event_ids():
		var e: WorldEvent = events[eid]
		if e.can_start_with(event_context(e)) == "":
			start_event(e, tick)
			return


## The facts WorldEvent.can_start_with reads for `e` now.
func event_context(e: WorldEvent) -> Dictionary:
	var p := _player()
	var cctx := Quests.condition_context()
	return {"stage": p.current_growth_stage() if p != null else 0, "flags": WorldState.flags, "condition_ctx": cctx,
		"now_s": clock_s(), "centre_ready": _ready_at(e.centre),
		"distance_m": _flat(p.global_position - _to_global(e.centre)) if p != null else INF}


## Starts `e` now (whatever its rules: tests use it directly): a run counted, its encounters copied, the
## folk its raiders hunt sent to shelter, its notice, its objective tracked, Events.world_event_started.
func start_event(e: WorldEvent, tick: int = Sim.tick) -> void:
	if e.is_running():
		return
	var run := e.runs(WorldState.flags) + 1
	WorldState.set_flag(WorldEvent.flag(e.id, "runs"), run)
	WorldState.set_flag(WorldEvent.flag(e.id, "last_start_s"), clock_s())
	e.runs_this_load += 1
	e.elapsed_s = 0.0
	e.unloaded_s = 0.0
	e.route = _event_route(e)
	e.state = WorldEvent.WAITING
	_carry_event(e, false)
	var text := str(e.record.get("start_text", ""))
	if text != "":
		Events.hud_message.emit(text, "warn")
	Events.world_event_started.emit(tick, e.id)
	if Quests.has_method("p37_set_event"):
		e.tracked_before = Quests.tracked_quest_id
		Quests.p37_set_event(e.id, event_objective(e))
		Quests.track(e.id)
	_begin_attempt(e, tick)


## Its encounters come into the world (when its start rule holds: its centre ready, the giant near) -
## WAITING until then.
func _begin_attempt(e: WorldEvent, tick: int) -> bool:
	var p := _player()
	if p == null or not _ready_at(e.centre) or _flat(p.global_position - _to_global(e.centre)) > e.start_radius():
		return false
	var scale := e.xp_scale_for_run(e.runs(WorldState.flags))
	e.copies.clear()
	for t: Variant in e.record.get("encounters", []):
		var tpl := GameData.get_record(str(t))
		if tpl.is_empty():
			continue
		_counter += 1
		var at := WorldEvent._vec3(tpl.get("center_m"))
		var yaw := 0.0
		if e.route != null:
			at = e.route.point_at()
			yaw = e.route.yaw_at()
		var rec := EncounterDirector.p37_copy_record(tpl, _counter, at, yaw, _ground_fn())
		var info := {"owner": "event", "event": e.id, "xp_scale": scale, "yaw": yaw, "march": e.route != null,
			"patrol": [] if e.route != null else target_points(e)}
		if director.p37_add_copy(rec, info):
			e.copies.append(str(rec.id))
	e.state = WorldEvent.RUNNING
	_shelter_folk(e, tick)
	if Quests.has_method("p37_set_event") and Quests.tracked_quest_id != e.id:
		Quests.p37_set_event(e.id, event_objective(e))
		Quests.track(e.id)   # each attempt leads the compass there (a death reload restored the old choice)
	return true


## The places of e's protected targets (level space, in their listed order; the index's, else a loaded
## prop's): the round its raiders walk while the event runs (they strike what they meet on the way).
func target_points(e: WorldEvent) -> Array:
	var out: Array = []
	var idx := _index()
	for t in e.targets():
		var p := idx.position_of(t) if idx != null else Vector3.INF
		if not p.is_finite():
			var prop := _prop_node(t)
			if prop != null and level != null:
				p = level.global_transform.affine_inverse() * prop.global_position
		if p.is_finite():
			out.append(p)
	return out


## The factions (short names) e's encounters hunt: their spawns' targets.
static func _hunted_factions(e: WorldEvent) -> Dictionary:
	var hunted := {}
	for t: Variant in e.record.get("encounters", []):
		for s: Variant in GameData.get_record(str(t)).get("spawns", []):
			if typeof(s) == TYPE_DICTIONARY and typeof(s.get("targets")) == TYPE_DICTIONARY:
				for f: Variant in (s.targets as Dictionary).get("factions", []):
					hunted[str(f).trim_prefix("faction.")] = true
	return hunted


## The folk of the factions its encounters hunt (their spawns' targets) near its centre take shelter (and
## those who come into the world while it runs: _on_member_spawned).
func _shelter_folk(e: WorldEvent, tick: int) -> void:
	var hunted := _hunted_factions(e)
	if hunted.is_empty() or not is_inside_tree():
		return
	var c0 := _to_global(e.centre)
	for n in get_tree().get_nodes_in_group("civilians"):
		var c := n as Civilian
		if c == null or not c.is_inside_tree() or c.brain == null or not hunted.has(c.faction):
			continue
		if _flat(c.global_position - c0) <= WorldEvent.SHELTER_RADIUS_M:
			c.brain.on_noise(tick, 0.0)


## One update of the running `e` (see world_event.gd): suspension, the march, the objective, the fail
## rule, the outcomes, the tracker's line.
func update_event(e: WorldEvent, dt: float, tick: int = Sim.tick) -> void:
	if e.state == WorldEvent.WAITING:
		if not _ready_at(e.centre):
			e.unloaded_s += dt
			if _abandoned(e):
				end_event(e, ABANDONED, tick)
			return
		if not _begin_attempt(e, tick):
			return
	if e.route != null and not e.copies.is_empty():
		if march(e.copies[0], e.route, dt) == "done" and e.end_outcome() != "":
			end_event(e, e.end_outcome(), tick)
			return
	if _ready_at(e.centre):
		e.state = WorldEvent.RUNNING
		e.unloaded_s = 0.0
		e.elapsed_s += dt
	else:
		e.state = WorldEvent.SUSPENDED
		e.unloaded_s += dt
		if _abandoned(e) and e.route == null:
			end_event(e, ABANDONED, tick)
			return
	var lose := e.lost_to_fail()
	if lose > 0 and e.lost_targets(_dead).size() >= lose and e.fail_outcome() != "":
		end_event(e, e.fail_outcome(), tick)
		return
	if _all_defeated(e):
		end_event(e, e.success_outcome(), tick)
		return
	var timer := float((e.record.get("fail", {}) as Dictionary).get("timer_s", 0.0)) if typeof(e.record.get("fail")) == TYPE_DICTIONARY else 0.0
	if timer > 0.0 and e.elapsed_s >= timer and e.fail_outcome() != "":
		end_event(e, e.fail_outcome(), tick)
		return
	_carry_event(e, false)
	if Quests.has_method("p37_set_event"):
		Quests.p37_set_event(e.id, event_objective(e))


func _abandoned(e: WorldEvent) -> bool:
	var limit := float(e.record.get("abandon_after_s", WorldEvent.DEFAULT_ABANDON_S))
	return limit > 0.0 and e.unloaded_s >= limit


func _all_defeated(e: WorldEvent) -> bool:
	if e.copies.is_empty():
		return false
	for id in e.copies:
		if not director.p37_defeated(id):
			return false
	return true


## Ends `e` with `outcome` (ABANDONED: no outcome at all): see world_event.gd.
func end_event(e: WorldEvent, outcome: String, tick: int = Sim.tick) -> void:
	if not e.is_running():
		return
	WorldState.set_flag(WorldEvent.flag(e.id, "last_end_s"), clock_s())
	var rec: Dictionary = (e.record.get("outcomes", {}) as Dictionary).get(outcome, {}) if outcome != ABANDONED else {}
	if outcome != ABANDONED:
		WorldState.set_flag(WorldEvent.flag(e.id, "done"), true)
		WorldState.set_flag(WorldEvent.flag(e.id, "outcome"), outcome)
		var flags: Variant = rec.get("set_flags", {})
		if typeof(flags) == TYPE_DICTIONARY:
			for f: Variant in flags:
				WorldState.try_set_flag(str(f), flags[f])
		if WorldState.try_set_flag(WorldEvent.reward_flag(e.id, outcome), true):
			var xp := int(rec.get("xp", 0))
			if xp > 0:
				Events.xp_award_requested.emit(xp, "event:%s" % e.id)
			for it: Variant in rec.get("items", []):
				if typeof(it) == TYPE_DICTIONARY:
					WorldState.add_item(str(it.get("item", "")), int(it.get("count", 1)), "event")
		_burn(e, int(rec.get("burn", 0)))
		var text := str(rec.get("text", ""))
		if text != "":
			Events.hud_message.emit(text, "good" if outcome == e.success_outcome() else "warn")
	var leaving := outcome == e.end_outcome() and outcome != ""
	for id in e.copies:
		if director.encounter_state(id) == EncounterDirector.DORMANT or (leaving and not copy_in_view(id)):
			_removals.append(id)   # nobody saw them / the column came home out of view: gone
		else:
			if not leaving:
				_rout_survivors(id)
			_copies[id] = {"table": "", "entry": "", "template": "", "route": null, "made_tick": tick,
				"active_seen": true, "cleared_tick": -1}   # the director drops them once the giant leaves
	e.log.append({"tick": tick, "outcome": outcome})
	e.copies.clear()
	e.route = null
	e.state = WorldEvent.IDLE
	e.elapsed_s = 0.0
	e.unloaded_s = 0.0
	(_carry.get(level.level_id, {}) as Dictionary).erase(e.id)
	if Quests.has_method("p37_clear_event"):
		Quests.p37_clear_event(e.id)
		if Quests.tracked_quest_id == e.id:
			var before := e.tracked_before
			Quests.tracked_quest_id = ""
			if before != "" and Quests.quest_state(before) == Quests.ACTIVE:
				Quests.track(before)
	Events.world_event_ended.emit(tick, e.id, outcome)
	if outcome != ABANDONED:
		GameSession.request_checkpoint("world_event")


## The giant died: the running event's attempt starts again (its copies go; see world_event.gd).
func reset_attempt(e: WorldEvent) -> void:
	if not e.is_running():
		return
	for id in e.copies:
		_removals.append(id)
	e.copies.clear()
	e.elapsed_s = 0.0
	e.unloaded_s = 0.0
	if e.route != null:
		e.route.s = e.route.start
	e.state = WorldEvent.WAITING
	_carry_event(e, true)


## Routs what is left of a copy (they leave the field: an event is over).
func _rout_survivors(id: String) -> void:
	for n: Node3D in director.p37_living(id):
		if n.has_method("p30_force_rout"):
			n.call("p30_force_rout")


## At least `n` of e's protected targets stand destroyed (the raiders' fire): the first standing ones, in
## their listed order, are burned - a loaded prop breaks in place, an unloaded one is recorded destroyed.
func _burn(e: WorldEvent, n: int) -> void:
	if n <= 0:
		return
	var lost := e.lost_targets(_dead).size()
	for t in e.targets():
		if lost >= n:
			return
		if WorldState.is_destroyed(t) or WorldState.is_killed(t):
			continue
		var prop := _prop_node(t)
		if prop != null and not prop.destroyed:
			prop.entity.combatant.pools.health = 0.0
			prop.entity.combatant.dead = true
			prop.on_entity_died("")
		else:
			WorldState.record_destroyed(t, 1)
		lost += 1


func _prop_node(world_id: String) -> BreakableProp:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("breakables"):
		if n is BreakableProp and (n as BreakableProp).world_id == world_id and (n as BreakableProp).is_inside_tree():
			return n as BreakableProp
	return null


## The tracker's, compass's, map's and journal's view of a running event (Quests' objective shape).
func event_objective(e: WorldEvent) -> Dictionary:
	var obj: Dictionary = e.record.get("objective", {}) if typeof(e.record.get("objective")) == TYPE_DICTIONARY else {}
	var total := e.targets().size()
	var standing := total - e.lost_targets(_dead).size()
	var text := str(obj.get("text", ""))
	text = WorldEvent.objective_text(text, standing, total) if text != "" else e.display_name()
	var pos := _to_global(e.centre)
	var marker := str(obj.get("marker", ""))
	if marker != "" and _index() != null and _index().position_of(marker).is_finite():
		pos = _to_global(_index().position_of(marker))
	if e.route != null:
		pos = _to_global(e.route.point_at())
	var bot: Dictionary = (e.record.get("bot", {}) as Dictionary).duplicate(true) if typeof(e.record.get("bot")) == TYPE_DICTIONARY else {}
	if bot.is_empty():
		bot = {"action": "protect" if str(obj.get("kind", "")) == "protect" else "fight_encounter", "event": e.id}
	return {"quest_id": e.id, "stage_id": e.state, "text": text, "kind": str(obj.get("kind", "")),
		"marker_id": marker, "position": pos, "targets": e.targets(), "bot": bot, "title": e.display_name(),
		"main": false, "stage_index": 0, "stage_count": 1, "markers": PackedStringArray(), "positions": [pos],
		"waiting_text": "", "via_exit": "", "via_name": "", "via_text": "", "event": true}


# --------------------------------------------------------------------------- deaths, reloads, respawns

func _on_entity_died(_tick: int, entity_id: String, _killer_id: String) -> void:
	_dead[entity_id] = true
	var p := _player()
	if p != null and p.entity != null and entity_id == p.entity.entity_id:
		var e := running_event()
		if e != null:
			reset_attempt(e)


## The title, a new game or a continue: a carried event belongs to the session left behind.
func _on_mode_change_requested(_mode: String, _options: Dictionary) -> void:
	_carry.clear()


func _carry_event(e: WorldEvent, reset: bool) -> void:
	if level == null:
		return
	if not _carry.has(level.level_id):
		_carry[level.level_id] = {}
	var at := e.centre
	if e.route != null:
		at = e.route.point_at()
	var prev: Dictionary = (_carry[level.level_id] as Dictionary).get(e.id, {})
	(_carry[level.level_id] as Dictionary)[e.id] = {"runs": e.runs(WorldState.flags),
		"last_start_s": WorldState.get_flag(WorldEvent.flag(e.id, "last_start_s"), clock_s()),
		"centre": at, "s": e.route.s if e.route != null else 0.0,
		"reset": reset or bool(prev.get("reset", false)), "tracked_before": e.tracked_before}


## A new load of the level: the events running when it was left run again - a death restarts their
## attempt from its beginning, a travel resumes them where they were.
func _resume_carried() -> void:
	if level == null or not _carry.has(level.level_id):
		return
	var carried: Dictionary = _carry[level.level_id]
	for eid: String in carried.keys():
		var e: WorldEvent = events.get(eid)
		if e == null:
			carried.erase(eid)
			continue
		var c: Dictionary = carried[eid]
		if e.runs(WorldState.flags) < int(c.get("runs", 0)):
			WorldState.set_flag(WorldEvent.flag(e.id, "runs"), int(c.runs))   # the reload rolled the start back
			WorldState.set_flag(WorldEvent.flag(e.id, "last_start_s"), c.get("last_start_s", clock_s()))
		e.state = WorldEvent.WAITING
		e.tracked_before = str(c.get("tracked_before", ""))
		e.route = _event_route(e)
		if e.route != null and not bool(c.get("reset", false)):
			e.route.s = clampf(float(c.get("s", e.route.start)), e.route.start, e.route.end_s())
		c["reset"] = false
		if Quests.has_method("p37_set_event"):
			Quests.p37_set_event(e.id, event_objective(e))


## GameSession's respawn blocker while this node lives (respawn_refusal).
func _respawn_blocker(checkpoint_id: String) -> String:
	return respawn_refusal(checkpoint_id)


## Why a respawn at `checkpoint_id` of the level GameSession asks about is refused ("" = it is not): within
## EVENT_CLEAR_M of an event running there (carried across its reloads), with the event's respawn_text.
static func respawn_refusal(checkpoint_id: String) -> String:
	var lv := GameSession.respawn_blocker_level()
	var carried: Dictionary = _carry.get(lv, {})
	if carried.is_empty():
		return ""
	var idx := WorldIndex.for_level(lv)
	if idx == null or not idx.has_checkpoint(checkpoint_id):
		return ""
	var at := idx.position_of(checkpoint_id)
	for eid: String in carried:
		var c: Vector3 = (carried[eid] as Dictionary).get("centre", Vector3.INF)
		if c.is_finite() and _flat(at - c) <= EVENT_CLEAR_M:
			var rec := GameData.get_record(eid)
			var text := str(rec.get("respawn_text", ""))
			return text if text != "" else RESPAWN_TEXT % str(rec.get("display_name", "A battle"))
	return ""


## True when `event_id` runs (or waits to resume) on `level_id` (tests, the bot).
static func is_carried(level_id: String, event_id: String) -> bool:
	return (_carry.get(level_id, {}) as Dictionary).has(event_id)


# --------------------------------------------------------------------------- the world around

func _find_level() -> LevelRoot:
	var n := get_parent()
	while n != null:
		if n is LevelRoot:
			return n as LevelRoot
		n = n.get_parent()
	return null


func _player() -> GiantPlayer:
	var p := level.player() if level != null else null
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or p.entity == null or not p.entity.is_alive():
		return null
	return p


func _index() -> WorldIndex:
	return level.index() if level != null else null


func _streamer() -> ChunkStreamer:
	var s: Variant = level.get("streamer") if level != null else null
	return s as ChunkStreamer if s is ChunkStreamer and (s as ChunkStreamer).configured else null


## True when the ground at `p` (level space) is loaded and ready (always on a level that is not streamed).
func _ready_at(p: Vector3) -> bool:
	var s := _streamer()
	if s == null:
		return true
	var c := s.chunk_at(_to_global(p))
	return c != "" and s.is_ready(c)


func _ground_ready(points: PackedVector3Array) -> bool:
	for p in points:
		if not _ready_at(p) or is_nan(_height(p)) and _streamer() != null:
			return false
	return true


## The loaded ground's height at `p` (NaN where none is loaded, or on a level without terrain data).
func _height(p: Vector3) -> float:
	if level != null and level.has_method("height_at"):
		return float(level.call("height_at", _to_global(p)))
	return NAN


func _ground_fn() -> Callable:
	return func(p: Vector3) -> float: return _height(p)


func _region_at(p: Vector3) -> String:
	if level != null and level.has_method("region_at"):
		return str(level.call("region_at", _to_global(p)))
	var idx := _index()
	return idx.region_at(p) if idx != null else ""


func _to_global(p: Vector3) -> Vector3:
	return level.global_transform * p if level != null and level.is_inside_tree() else p


## The anchor on the human navmesh (within NAV_SNAP_M), or Vector3.INF - one query of the tick's budget
## (none left: INF, and the place waits). A level without navigation takes the anchor as it is.
func _snap(anchor: Vector3) -> Vector3:
	if not NavQuery.has_navigation(level, NAV_LAYER):
		return anchor
	if NavQuery.budget_left(level) <= 0:
		return Vector3.INF
	var q := NavQuery.closest_point(level, _to_global(anchor), NAV_LAYER)
	if not q.is_finite() or _flat(q - _to_global(anchor)) > NAV_SNAP_M:
		return Vector3.INF
	return q


## True when a living member of copy `id` stands in the camera's view.
func copy_in_view(id: String) -> bool:
	for n: Node3D in director.p37_living(id):
		if in_view(n.global_position):
			return true
	return false


func _any_in_view(points: PackedVector3Array) -> bool:
	for p in points:
		if in_view(_to_global(p)):
			return true
	return false


## True when a point (global) is in the camera's view (view_probe in tests).
func in_view(p: Vector3) -> bool:
	if view_probe.is_valid():
		return bool(view_probe.call(p))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam != null and cam.is_position_in_frustum(p + Vector3.UP)


## True when `anchor` keeps clear of settlements, placed encounters not cleared, other copies and
## running events.
func _clear_of_others(anchor: Vector3) -> bool:
	var idx := _index()
	if idx != null:
		for id: String in idx.pois:
			var poi: Dictionary = idx.pois[id]
			if str(poi.get("kind", "")) == "settlement" and _flat(anchor - (poi.position as Vector3)) <= float(poi.get("radius", 0.0)) + SETTLEMENT_MARGIN_M:
				return false
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if bool(rec.get("template", false)) or str(rec.get("level", "")) != level.level_id:
			continue
		if _flat(anchor - WorldEvent._vec3(rec.get("center_m"))) <= ENCOUNTER_GAP_M \
				and director.encounter_state(str(rec.id)) != EncounterDirector.CLEARED:
			return false
	for id in copy_ids():
		var info := director.p37_copy_info(id)
		if not info.is_empty() and _flat(anchor - (info.get("centre", Vector3.INF) as Vector3)) <= COPY_GAP_M:
			return false
	var e := running_event()
	if e != null and _flat(anchor - e.centre) <= EVENT_CLEAR_M:
		return false
	return true


func _index_ids(table: String) -> PackedStringArray:
	var idx := _index()
	var out := PackedStringArray((idx.get(table) as Dictionary).keys()) if idx != null else PackedStringArray()
	out.sort()
	return out


## The road nodes of each region and the road graph's neighbours (from the level's world index).
func _build_roads() -> void:
	_roads.clear()
	_adjacent.clear()
	var idx := _index()
	if idx == null:
		return
	var nodes := idx.road_nodes()
	var edges := idx.road_edges()
	for i in nodes.size():
		var r := idx.region_at(nodes[i])
		if r == "":
			continue
		var in_region: PackedInt32Array = _roads.get(r, PackedInt32Array())
		in_region.append(i)
		_roads[r] = in_region   # a packed array is a value: store it back
	for k in range(edges.size() / 2):
		var a := edges[2 * k]
		var b := edges[2 * k + 1]
		if a < 0 or b < 0 or a >= nodes.size() or b >= nodes.size():
			continue
		var d := _flat(nodes[a] - nodes[b])
		if not _adjacent.has(a):
			_adjacent[a] = []
		if not _adjacent.has(b):
			_adjacent[b] = []
		(_adjacent[a] as Array).append([b, d])
		(_adjacent[b] as Array).append([a, d])


## The heading along the road at node `i` (toward its first neighbour).
func _road_yaw(i: int) -> float:
	var nb: Array = _adjacent.get(i, [])
	var idx := _index()
	if nb.is_empty() or idx == null:
		return 0.0
	var d := idx.road_nodes()[int((nb[0] as Array)[0])] - idx.road_nodes()[i]
	return TargetingRules.yaw_of(Vector3(d.x, 0.0, d.z))


static func _interval(table: Dictionary) -> float:
	var iv: Variant = table.get("interval_s", DEFAULT_INTERVAL_S)
	if typeof(iv) != TYPE_ARRAY or (iv as Array).size() != 2:
		iv = DEFAULT_INTERVAL_S
	return Sim.rng_for("wander").randf_range(float(iv[0]), float(iv[1]))


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Lines for the F3 debug panel.
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var e := running_event()
	lines.append("WANDER %s  copies %d  spawns %d  event %s" % [level.level_id if level != null else "?",
		copy_ids().size(), spawn_log.size(), "%s (%s, %.0f s)" % [e.id, e.state, e.elapsed_s] if e != null else "-"])
	for id in copy_ids():
		lines.append("  %s: %s" % [id, director.encounter_state(id)])
	return lines
