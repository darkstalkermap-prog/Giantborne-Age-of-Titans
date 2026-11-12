class_name WorldMetrics
extends RefCounted
## The world bot's metrics (P38; plan M6-M9 §6.1 "Metrics"), beside the Valley's RunMetrics (which
## keeps counting what it counts in the world: deaths with causes, damage by archetype and action,
## readability, time-to-kill, the AI-state histogram, ability use, actions, the XP timeline, growth,
## stuck events, rewards, node counts) and whose segments the world bot points at §5.15's world
## segments (WORLD_SEGMENTS). This adds what only the world has, for AUTOPILOT_RESULT's
## "world_bot.world" block and P39's balance pass:
##   * time per region and per growth stage, regions entered (first tick), POIs discovered (with
##     their kind), sealed places opened, cairns read;
##   * the XP floors the main thread applied (an award above its stage's own xp), iron and titan iron
##     over time;
##   * oath and boss outcomes, boss engagements, attempts (a disengage starts a new one), phases and
##     yields;
##   * formation stats (group and banner locks at stages 4-6 with formations near, banners felled,
##     formations broken and routed, Formation Sweep uses), siege stats (engines destroyed, engines
##     thrown, engine shots at the giant), wander spawns, world events (starts and outcomes);
##   * fast travels (and refusals), map screens, level loads;
##   * streaming (the streamer's loads, unloads, thrash, worst work frame, the smallest margin to
##     unloaded ground), path queries per tick (NavQuery.queries_total per tick: p95, max), the music
##     intensity histogram per stage (explore / danger / combat seconds, while audio runs), the
##     largest save written.
## The human estimate's world terms (plan §6.1: 6 s per map screen, 4 s per fast-travel load, 10 s
## per region entered first, 5 s per POI discovered, 8 s per sealed place opened) go to the current
## RunMetrics segment through RunMetrics.add_to_segment, so each segment's estimate carries its own.

const TICK_S := 1.0 / 60.0
const HUMAN_MAP_S := 6.0
const HUMAN_FAST_TRAVEL_S := 4.0
const HUMAN_REGION_S := 10.0
const HUMAN_POI_S := 5.0
const HUMAN_SEALED_S := 8.0
const ITEM_IRON := "item.iron_ingot"
const ITEM_TITAN := "item.titan_iron"
const MARGIN_EVERY_TICKS := 30
const QUERY_HIST_MAX := 64

var run_metrics: RunMetrics = null
var regions: Dictionary = {}          ## region id -> {"s", "first_tick"}
var stage_s: Dictionary = {}          ## stage (String) -> seconds
var discoveries: Array = []           ## [tick, poi id, kind]
var sealed_opened: Array = []         ## [tick, poi id]
var cairns: Array = []                ## [tick, flag]
var xp_floors: Array = []             ## [tick, source, awarded, stage xp]
var items: Array = []                 ## [tick, iron, titan iron] on every change
var oaths: Dictionary = {}            ## march|wood|crown -> {"outcome", "tick"}
var bosses: Dictionary = {}           ## boss id -> {"engaged", "attempts", "phases": [], "yields", "outcome", "disengaged": []}
var formations := {"group_lock_samples": 0, "banner_lock_samples": 0, "single_lock_samples": 0,
	"banners_felled": 0, "broken": 0, "routed": 0, "sweeps": 0, "seen": 0}
var siege := {"engines_destroyed": 0, "engines_thrown": 0, "shots_at_giant": 0, "destroyed_ids": []}
var wander := {"spawns": 0, "by_template": {}}
var world_events: Dictionary = {}     ## event id -> {"started", "outcomes": []}
var fast_travels: Array = []          ## [tick, from checkpoint, to checkpoint, ok, message]
var map_screens := 0
var loads := 0
var min_margin_m := INF
var streaming: Dictionary = {}        ## the last streamer stats seen (per load, merged)
var stream_totals := {"loads": 0, "unloads": 0, "thrash": 0, "work_ms_max": 0.0}
var query_hist: Dictionary = {}       ## queries in a tick -> ticks
var music: Dictionary = {}            ## stage -> {"explore", "danger", "combat", "silent"} seconds
var save_bytes_max := 0
var deaths_by_region: Dictionary = {}
var refusals: Array = []              ## [tick, what, message] (fast travel and other refusals)

var _connected := false
var _last_tick := -1
var _queries_before := -1
var _iron_last := -1
var _titan_last := -1
var _region := ""
var _streamer_ref: WeakRef = null


func _init(p_run_metrics: RunMetrics = null) -> void:
	run_metrics = p_run_metrics


# --------------------------------------------------------------------------- events

func connect_events() -> void:
	if _connected:
		return
	_connected = true
	for pair: Array in _listeners():
		if not (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).connect(pair[1])


func disconnect_events() -> void:
	if not _connected:
		return
	_connected = false
	for pair: Array in _listeners():
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _listeners() -> Array:
	return [
		[Events.region_changed, _on_region_changed],
		[Events.poi_discovered, _on_poi_discovered],
		[Events.flag_changed, _on_flag_changed],
		[Events.xp_award_requested, _on_xp_award],
		[Events.boss_engaged, _on_boss_engaged],
		[Events.boss_phase_changed, _on_boss_phase],
		[Events.boss_yielded, _on_boss_yielded],
		[Events.boss_disengaged, _on_boss_disengaged],
		[Events.boss_defeated, _on_boss_defeated],
		[Events.formation_changed, _on_formation_changed],
		[Events.siege_engine_fired, _on_engine_fired],
		[Events.object_destroyed, _on_object_destroyed],
		[Events.wander_spawned, _on_wander_spawned],
		[Events.world_event_started, _on_event_started],
		[Events.world_event_ended, _on_event_ended],
		[Events.checkpoint_saved, _on_checkpoint_saved],
		[Events.entity_died, _on_entity_died],
		[Events.ability_started, _on_ability_started],
		[Events.grab_ended, _on_grab_ended],
	]


func _on_region_changed(tick: int, region_id: String, _previous: String) -> void:
	_region = region_id
	if region_id == "" or regions.has(region_id):
		return
	regions[region_id] = {"s": 0.0, "first_tick": tick}
	_add_human("regions_entered", 1)


func _on_poi_discovered(tick: int, poi_id: String) -> void:
	var kind := str(GameData.get_record(poi_id).get("kind", ""))
	discoveries.append([tick, poi_id, kind])
	_add_human("pois", 1)
	if kind == "secret":
		sealed_opened.append([tick, poi_id])
		_add_human("sealed", 1)


func _on_flag_changed(tick: int, flag_id: String, value: Variant) -> void:
	if flag_id.begins_with("oath.") and flag_id.ends_with(".outcome") and str(value) != "":
		var oath := flag_id.trim_prefix("oath.").trim_suffix(".outcome")
		if not oaths.has(oath):
			oaths[oath] = {"outcome": str(value), "tick": tick}
	elif flag_id.begins_with("boss.") and flag_id.ends_with(".outcome") and str(value) != "":
		var b := flag_id.trim_prefix("boss.").trim_suffix(".outcome")
		var rec := _boss(b)
		rec.outcome = str(value)
	elif flag_id.begins_with("reward.") and flag_id.contains("cairn") and QuestConditions.truthy(value):
		cairns.append([tick, flag_id])


func _on_xp_award(amount: int, source: String) -> void:
	if not source.begins_with("quest:"):
		return
	var parts := source.split(":")
	if parts.size() < 3:
		return
	var srec := Quests.stage_record(Quests.quest_record(parts[1]), parts[2])
	var own := int(srec.get("xp", 0))
	if amount > own:
		xp_floors.append([Sim.tick, source, amount, own])


func _boss(id: String) -> Dictionary:
	if not bosses.has(id):
		bosses[id] = {"engaged": 0, "attempts": 0, "phases": [], "yields": 0, "outcome": "", "disengaged": [],
			"defeated": false}
	return bosses[id]


## An engagement opens an attempt unless one is open: a disengage, a defeat, a yield's decision or a
## level load (a death's reload) closes it.
func _on_boss_engaged(tick: int, boss_id: String) -> void:
	var b := _boss(boss_id)
	b.engaged = int(b.engaged) + 1
	if not bool(b.get("open", false)):
		b.attempts = int(b.attempts) + 1
		b.open = true
	b["last_engaged"] = tick


func _on_boss_phase(tick: int, boss_id: String, phase: int) -> void:
	(_boss(boss_id).phases as Array).append([tick, phase])


func _on_boss_yielded(_tick: int, boss_id: String) -> void:
	var b := _boss(boss_id)
	b.yields = int(b.yields) + 1


func _on_boss_disengaged(tick: int, boss_id: String, reason: String) -> void:
	var b := _boss(boss_id)
	(b.disengaged as Array).append([tick, reason])
	b.open = false


func _on_boss_defeated(_tick: int, boss_id: String) -> void:
	var b := _boss(boss_id)
	b.defeated = true
	b.open = false


func _on_formation_changed(_tick: int, _formation_id: String, state: String) -> void:
	match state:
		"banner_fell":
			formations.banners_felled = int(formations.banners_felled) + 1
		"broken":
			formations.broken = int(formations.broken) + 1
		"routed":
			formations.routed = int(formations.routed) + 1
		"formed":
			formations.seen = int(formations.seen) + 1


func _on_engine_fired(_tick: int, _engine_id: String, _action_id: String, target_id: String) -> void:
	if target_id == RunMetrics.PLAYER_ID:
		siege.shots_at_giant = int(siege.shots_at_giant) + 1


func _on_object_destroyed(_tick: int, world_id: String, _by: String) -> void:
	var e := Sim.get_entity(world_id)
	if e != null and e.actor is SiegeEngine:
		siege.engines_destroyed = int(siege.engines_destroyed) + 1
		(siege.destroyed_ids as Array).append(world_id)


func _on_grab_ended(_tick: int, holder_id: String, target_id: String, reason: String) -> void:
	if holder_id != RunMetrics.PLAYER_ID or reason != "thrown":
		return
	var e := Sim.get_entity(target_id)
	if e != null and e.actor is SiegeEngine:
		siege.engines_thrown = int(siege.engines_thrown) + 1


func _on_wander_spawned(_tick: int, template_id: String, _encounter_id: String) -> void:
	wander.spawns = int(wander.spawns) + 1
	var by: Dictionary = wander.by_template
	by[template_id] = int(by.get(template_id, 0)) + 1


func _on_event_started(_tick: int, event_id: String) -> void:
	var e: Dictionary = world_events.get(event_id, {"started": 0, "outcomes": []})
	e.started = int(e.started) + 1
	world_events[event_id] = e


func _on_event_ended(_tick: int, event_id: String, outcome: String) -> void:
	var e: Dictionary = world_events.get(event_id, {"started": 0, "outcomes": []})
	(e.outcomes as Array).append(outcome)
	world_events[event_id] = e


func _on_checkpoint_saved(_tick: int, _checkpoint_id: String, ok: bool, _message: String) -> void:
	if not ok:
		return
	var path := SaveSlots.path()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			save_bytes_max = maxi(save_bytes_max, int(f.get_length()))
			f.close()


func _on_entity_died(_tick: int, entity_id: String, _killer: String) -> void:
	if entity_id == RunMetrics.PLAYER_ID:
		var r := _region if _region != "" else "(none)"
		deaths_by_region[r] = int(deaths_by_region.get(r, 0)) + 1


func _on_ability_started(_tick: int, actor_id: String, action_id: String, _instance: int) -> void:
	if actor_id == RunMetrics.PLAYER_ID and action_id == "ability.formation_sweep":
		formations.sweeps = int(formations.sweeps) + 1


# --------------------------------------------------------------------------- the bot reports

## A level (re)load: the streamer of this level is read from now on.
func note_level_loaded(world: Node) -> void:
	loads += 1
	for id: String in bosses:
		(bosses[id] as Dictionary).open = false   # a reload (a death) ends the attempt
	_fold_streamer()
	_streamer_ref = null
	if world != null and "streamer" in world and world.get("streamer") is ChunkStreamer:
		_streamer_ref = weakref(world.get("streamer"))
		_region = str(world.get("region_id")) if "region_id" in world else ""


func note_fast_travel(tick: int, from_id: String, to_id: String, ok: bool, message: String) -> void:
	fast_travels.append([tick, from_id, to_id, ok, message])
	map_screens += 1
	_add_human("map_screens", 1)
	if ok:
		_add_human("fast_travels", 1)
	else:
		refusals.append([tick, "fast_travel %s" % to_id, message])


func note_refusal(tick: int, what: String, message: String) -> void:
	refusals.append([tick, what, message])
	if refusals.size() > 100:
		refusals.remove_at(0)


func _add_human(field: String, amount: int) -> void:
	if run_metrics != null:
		run_metrics.add_to_segment(field, amount)


## Once per simulation tick: region and stage time, the lock kind at stages 4-6 with formations
## near, the margin to unloaded ground (every MARGIN_EVERY_TICKS), path queries this tick, the
## music's intensity, the iron and titan iron held.
func on_tick(tick: int, player: GiantPlayer, world: Node) -> void:
	if tick == _last_tick:
		return
	_last_tick = tick
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var stage := str(player.current_growth_stage())
	stage_s[stage] = float(stage_s.get(stage, 0.0)) + TICK_S
	if world != null and is_instance_valid(world) and "region_id" in world:
		var r := str(world.get("region_id"))
		if r != "":
			_region = r
			var rec: Dictionary = regions.get(r, {"s": 0.0, "first_tick": tick})
			rec.s = float(rec.s) + TICK_S
			regions[r] = rec
	var q := NavQuery.queries_total
	if _queries_before >= 0:
		var n := mini(q - _queries_before, QUERY_HIST_MAX)
		query_hist[n] = int(query_hist.get(n, 0)) + 1
	_queries_before = q
	if player.current_growth_stage() >= 4 and not Formation.live().is_empty():
		_sample_lock(player)
	if tick % MARGIN_EVERY_TICKS == 0 and _streamer_ref != null:
		var s := _streamer_ref.get_ref() as ChunkStreamer
		if s != null:
			min_margin_m = minf(min_margin_m, WorldWalk.margin_to_unloaded(s, player.global_position))
	_sample_music(stage)
	var iron := WorldState.count_of(ITEM_IRON)
	var titan := WorldState.count_of(ITEM_TITAN)
	if iron != _iron_last or titan != _titan_last:
		_iron_last = iron
		_titan_last = titan
		items.append([tick, iron, titan])


func _sample_lock(player: GiantPlayer) -> void:
	if player.targeting == null or not player.lock.is_locked():
		return
	if player.targeting.is_group_locked():
		formations.group_lock_samples = int(formations.group_lock_samples) + 1
		return
	var e := player.targeting.locked_entity()
	var a := e.actor as EnemyActor if e != null else null
	if a != null and a.formation != null and a.formation_slot == Formation.BANNER_SLOT:
		formations.banner_lock_samples = int(formations.banner_lock_samples) + 1
	else:
		formations.single_lock_samples = int(formations.single_lock_samples) + 1


func _sample_music(stage: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio: Node = tree.root.get_node_or_null("Audio") if tree != null else null
	var key := "off"
	if audio != null and bool(audio.get("enabled")) and audio.get("music") != null:
		var m: Object = audio.get("music")
		key = str(m.get("intensity")) if "intensity" in m else "off"
	var by: Dictionary = music.get(stage, {})
	by[key] = snappedf(float(by.get(key, 0.0)) + TICK_S, 0.001)
	music[stage] = by


## The streamer's counters of the level now ending (each load starts its own).
func _fold_streamer() -> void:
	if _streamer_ref == null:
		return
	var s := _streamer_ref.get_ref() as ChunkStreamer
	if s == null:
		return
	var st := s.stats()
	stream_totals.loads = int(stream_totals.loads) + int(st.get("loads", 0))
	stream_totals.unloads = int(stream_totals.unloads) + int(st.get("unloads", 0))
	stream_totals.thrash = int(stream_totals.thrash) + int(st.get("thrash", 0))
	stream_totals.work_ms_max = maxf(float(stream_totals.work_ms_max), float(st.get("work_ms_max", 0.0)))
	streaming = st


# --------------------------------------------------------------------------- the result

## Percentile of the per-tick query histogram.
func _query_percentile(p: float) -> int:
	var total := 0
	for k: Variant in query_hist:
		total += int(query_hist[k])
	if total == 0:
		return 0
	var keys := query_hist.keys()
	keys.sort()
	var want := p * float(total)
	var acc := 0
	for k: Variant in keys:
		acc += int(query_hist[k])
		if float(acc) >= want:
			return int(k)
	return int(keys.back())


func result() -> Dictionary:
	_fold_streamer()
	var region_out := {}
	for r: String in regions:
		region_out[r] = {"s": snappedf(float(regions[r].s), 0.01), "first_tick": int(regions[r].first_tick)}
	var stage_out := {}
	for s: String in stage_s:
		stage_out[s] = snappedf(float(stage_s[s]), 0.01)
	var q_max := 0
	for k: Variant in query_hist:
		q_max = maxi(q_max, int(k))
	var formation_locks := int(formations.group_lock_samples) + int(formations.banner_lock_samples)
	var all_locks := formation_locks + int(formations.single_lock_samples)
	return {
		"regions": region_out,
		"stage_s": stage_out,
		"discoveries": discoveries.duplicate(true),
		"discovered": discoveries.size(),
		"sealed_opened": sealed_opened.duplicate(true),
		"cairns": cairns.duplicate(true),
		"xp_floors": xp_floors.duplicate(true),
		"items": items.duplicate(true),
		"oaths": oaths.duplicate(true),
		"bosses": bosses.duplicate(true),
		"formations": formations.duplicate(true),
		"formation_lock_share": snappedf(float(formation_locks) / float(all_locks), 0.001) if all_locks > 0 else -1.0,
		"siege": siege.duplicate(true),
		"wander": wander.duplicate(true),
		"world_events": world_events.duplicate(true),
		"fast_travels": fast_travels.duplicate(true),
		"map_screens": map_screens,
		"level_loads": loads,
		"streaming": {"loads": stream_totals.loads, "unloads": stream_totals.unloads, "thrash": stream_totals.thrash,
			"work_ms_max": stream_totals.work_ms_max, "min_margin_m": snappedf(min_margin_m, 0.1) if min_margin_m != INF else -1.0,
			"last": streaming.duplicate(true)},
		"path_queries_per_tick": {"p50": _query_percentile(0.5), "p95": _query_percentile(0.95), "max": q_max},
		"music": music.duplicate(true),
		"save_bytes_max": save_bytes_max,
		"deaths_by_region": deaths_by_region.duplicate(),
		"refusals": refusals.duplicate(true),
	}
