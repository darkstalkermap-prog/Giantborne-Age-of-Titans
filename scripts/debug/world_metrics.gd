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
## How often the streamer's counters are snapshotted (a reload frees the streamer before its level's
## end is announced: the snapshot keeps its counts).
const STATS_EVERY_TICKS := 120
const QUERY_HIST_MAX := 64
## P39: the growth and lesser-music samples are taken this often (ticks).
const GROWTH_SAMPLE_TICKS := 6
## P39: the soldiers, archers and mages that §6.4's "lone humans" are when no formation holds them.
const HUMAN_ARCHETYPES := ["soldier", "archer", "mage"]
## P39: a lone human's states that count as fleeing (§6.4: "flee or rout").
const FLED_STATES := ["Flee", "Routed"]

var run_metrics: RunMetrics = null
var regions: Dictionary = {}          ## region id -> {"s", "first_tick"}
var stage_s: Dictionary = {}          ## stage (String) -> seconds
var discoveries: Array = []           ## [tick, poi id, kind]
var sealed_opened: Array = []         ## [tick, poi id]
var cairns: Array = []                ## [tick, flag]
var xp_floors: Array = []             ## [tick, source, awarded, stage xp]
var items: Array = []                 ## [tick, iron, titan iron] on every change
var oaths: Dictionary = {}            ## march|wood|crown -> {"outcome", "tick"}
## The boss outcome flags' names (boss.<name>.outcome) and the ids their engagements carry.
const BOSS_IDS := {"matriarch": "world.greywood.troll_matriarch", "harrok": "world.stonehold.harrok",
	"corvane": "battle.iron_regiment"}
var bosses: Dictionary = {}           ## boss id -> {"engaged", "attempts", "phases": [], "yields", "outcome", "disengaged": []}
var formations := {"group_lock_samples": 0, "banner_lock_samples": 0, "single_lock_samples": 0,
	"banners_felled": 0, "broken": 0, "routed": 0, "sweeps": 0, "seen": 0}
var siege := {"engines_destroyed": 0, "engines_thrown": 0, "shots_at_giant": 0, "destroyed_ids": []}
var wander := {"spawns": 0, "by_template": {}}
var world_events: Dictionary = {}     ## event id -> {"started", "outcomes": [], "ticks": [[start, end, outcome]]}
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
## P39 (plan §6.4 "growth shows" and "readability"), sampled every GROWTH_SAMPLE_TICKS at stages 4-6
## among the enemies engaged with the giant (alive, aware, hostile, within RunMetrics.HOSTILE_NEAR_M):
##   * lone humans (a soldier, archer or mage in no intact formation, serving no engine, no boss):
##     their engaged seconds and the seconds they spent fleeing or routed;
##   * formations whose banner lives and that have such an engaged member: their engaged seconds and
##     the seconds they held (formed, advancing or braced: Formation.is_intact);
##   * stage seconds with only lesser enemies engaged (none the music director counts: shorter than
##     its lesser_height_ratio of the giant and not special - MusicDirector.is_special) and the music's
##     intensity over them.
## The formation lock samples are taken only while a formation is engaged so (P38 sampled whenever
## any formation lived in the loaded world: a troll fight 300 m from a war camp counted).
var growth := {"lone_engaged_s": 0.0, "lone_fled_s": 0.0, "formation_engaged_s": 0.0, "formation_held_s": 0.0}
var music_lesser: Dictionary = {}     ## intensity -> seconds while only lesser enemies are engaged (stages 4-6)
## P39: the lone humans' engaged seconds by "<archetype>/<brain state>" (what they do when they do not flee).
var lone_states: Dictionary = {}
var _formation_engaged := false

var _connected := false
var _last_tick := -1
var _queries_before := -1
var _iron_last := -1
var _titan_last := -1
var _region := ""
var _streamer_ref: WeakRef = null
var _stream_snapshot: Dictionary = {}


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
		[Events.hit_resolved, _on_hit_resolved],
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
		var rec := _boss(str(BOSS_IDS.get(b, b)))
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
			"defeated": false, "lows": []}
	return bosses[id]


## P39: closes boss `b`'s open attempt: its lowest health share joins "lows" (one per attempt).
func _close_attempt(b: Dictionary) -> void:
	if bool(b.get("open", false)):
		(b.lows as Array).append(snappedf(float(b.get("low", 1.0)), 0.001))
	b.open = false
	b.erase("low")


## An engagement opens an attempt unless one is open: a disengage, a defeat, a yield's decision or a
## level load (a death's reload) closes it.
func _on_boss_engaged(tick: int, boss_id: String) -> void:
	var b := _boss(boss_id)
	b.engaged = int(b.engaged) + 1
	if not bool(b.get("open", false)):
		b.attempts = int(b.attempts) + 1
		b.open = true
		b["low"] = 1.0
		_sample_boss(boss_id, b)
	b["last_engaged"] = tick


func _on_boss_phase(tick: int, boss_id: String, phase: int) -> void:
	(_boss(boss_id).phases as Array).append([tick, phase])


func _on_boss_yielded(_tick: int, boss_id: String) -> void:
	var b := _boss(boss_id)
	b.yields = int(b.yields) + 1


func _on_boss_disengaged(tick: int, boss_id: String, reason: String) -> void:
	var b := _boss(boss_id)
	(b.disengaged as Array).append([tick, reason])
	_close_attempt(b)


func _on_boss_defeated(_tick: int, boss_id: String) -> void:
	var b := _boss(boss_id)
	_sample_boss(boss_id, b)
	b.defeated = true
	_close_attempt(b)


## P39: the open attempt's lowest health share of boss `id` so far - an enemy's health over its maximum,
## a battle's aggregate fraction (BattleBoss.aggregate_fraction) - so a fight lost is told from one
## nearly won (the M8 release check: the Iron Regiment's bar never fell below 62 %).
func _sample_boss(id: String, b: Dictionary) -> void:
	var frac := -1.0
	var e := Sim.get_entity(id)
	if e != null and e.combatant != null and e.combatant.pools.health_max > 0.0:
		frac = e.combatant.pools.health / e.combatant.pools.health_max if e.is_alive() else 0.0
	elif Engine.get_main_loop() is SceneTree:
		for n in (Engine.get_main_loop() as SceneTree).get_nodes_in_group(BattleBoss.BATTLE_GROUP):
			var bb := n as BattleBoss
			if bb != null and bb.battle_id == id and bb.total_health() > 0.0:
				frac = bb.aggregate_fraction()
	if frac >= 0.0:
		b["low"] = minf(float(b.get("low", 1.0)), frac)


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


## P39: the damage the giant takes while a boss fight is engaged, by the attacker's archetype, in each
## engaged boss's record ("damage_taken_by": the M8 release check measured the Iron Regiment's fort
## ballistae dealing about 85 % of it).
func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or r.event.target_id != RunMetrics.PLAYER_ID or r.health_damage <= 0:
		return
	var fights := GameSession.engaged_fights()
	if fights.is_empty():
		return
	var e := Sim.get_entity(r.event.attacker_id)
	var arch := RunMetrics.archetype_of(e) if e != null else "unknown"
	for id: String in fights:
		var b := _boss(id)
		var by: Dictionary = b.get("damage_taken_by", {})
		by[arch] = int(by.get(arch, 0)) + r.health_damage
		b["damage_taken_by"] = by


func _on_wander_spawned(_tick: int, template_id: String, _encounter_id: String) -> void:
	wander.spawns = int(wander.spawns) + 1
	var by: Dictionary = wander.by_template
	by[template_id] = int(by.get(template_id, 0)) + 1


func _on_event_started(tick: int, event_id: String) -> void:
	var e: Dictionary = world_events.get(event_id, {"started": 0, "outcomes": [], "ticks": []})
	e.started = int(e.started) + 1
	(e.get_or_add("ticks", []) as Array).append([tick, -1, ""])
	world_events[event_id] = e


func _on_event_ended(tick: int, event_id: String, outcome: String) -> void:
	var e: Dictionary = world_events.get(event_id, {"started": 0, "outcomes": [], "ticks": []})
	(e.outcomes as Array).append(outcome)
	var ticks: Array = e.get_or_add("ticks", [])
	if not ticks.is_empty() and int(ticks[-1][1]) < 0:
		ticks[-1][1] = tick
		ticks[-1][2] = outcome
	else:
		ticks.append([-1, tick, outcome])
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
		_close_attempt(bosses[id])   # a reload (a death) ends the attempt
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
	if tick % GROWTH_SAMPLE_TICKS == 0:
		for id: String in bosses:
			if bool((bosses[id] as Dictionary).get("open", false)):
				_sample_boss(id, bosses[id])
	if player.current_growth_stage() >= 4:
		if tick % GROWTH_SAMPLE_TICKS == 0:
			_sample_growth(player)
		if _formation_engaged:
			_sample_lock(player)
	else:
		_formation_engaged = false
	if tick % MARGIN_EVERY_TICKS == 0 and _streamer_ref != null:
		var s := _streamer_ref.get_ref() as ChunkStreamer
		if s != null:
			min_margin_m = minf(min_margin_m, WorldWalk.margin_to_unloaded(s, player.global_position))
			if tick % STATS_EVERY_TICKS == 0:
				_stream_snapshot = s.stats()
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


## P39: one growth sample (every GROWTH_SAMPLE_TICKS at stages 4-6; see `growth`): the lone humans
## and the formations engaged with the giant, whether a formation is engaged (the lock samples' gate)
## and, when only lesser enemies are engaged, the music's intensity.
func _sample_growth(player: GiantPlayer) -> void:
	var dt := float(GROWTH_SAMPLE_TICKS) * TICK_S
	var tree := player.get_tree()
	var ppos := player.global_position
	var player_h := player.entity.combatant.height_m if player.entity != null and player.entity.combatant != null else 1.8
	var engaged_formations := {}
	var engaged := 0
	var counting := 0
	for n in tree.get_nodes_in_group("enemies"):
		var a := n as EnemyActor
		if not engaged_with(a, ppos):
			continue
		engaged += 1
		if counts_for_music(a, player_h, _lesser_ratio()):
			counting += 1
		var f := a.formation
		if f != null and not f.dissolved and f.banner_alive():
			engaged_formations[f] = true
		if is_lone_human(a):
			growth.lone_engaged_s = float(growth.lone_engaged_s) + dt
			var st := a.brain.state_name()
			if st in FLED_STATES:
				growth.lone_fled_s = float(growth.lone_fled_s) + dt
			var key := "%s/%s" % [RunMetrics.archetype_of(a.entity), st]
			lone_states[key] = snappedf(float(lone_states.get(key, 0.0)) + dt, 0.001)
	for f: Formation in engaged_formations:
		growth.formation_engaged_s = float(growth.formation_engaged_s) + dt
		if f.is_intact():
			growth.formation_held_s = float(growth.formation_held_s) + dt
	_formation_engaged = not engaged_formations.is_empty()
	if engaged > 0 and counting == 0:
		var key := _music_key()
		music_lesser[key] = snappedf(float(music_lesser.get(key, 0.0)) + dt, 0.001)


## P39: an enemy engaged with the giant at `ppos` - alive, aware, hostile and within
## RunMetrics.HOSTILE_NEAR_M (the AI-state histogram's own rule).
static func engaged_with(a: EnemyActor, ppos: Vector3) -> bool:
	if a == null or not a.is_inside_tree() or a.entity == null or not a.entity.is_alive() or a.brain == null:
		return false
	if not a.brain.aware or a.entity.team != CombatEntity.Team.ENEMY:
		return false
	return a.global_position.distance_to(ppos) <= RunMetrics.HOSTILE_NEAR_M


## P39: a lone human (§6.4): a soldier, archer or mage that no intact formation holds, that serves no
## engine (a crew) and is no boss (Corvane).
static func is_lone_human(a: EnemyActor) -> bool:
	if a == null or a.entity == null or a.entity.combatant == null or a.is_in_group("bosses"):
		return false
	var rec: Dictionary = a.entity.combatant.base_record
	if not (str(rec.get("archetype", "")) in HUMAN_ARCHETYPES) or str(rec.get("role", "")) == "crew":
		return false
	return a.formation == null or a.formation.dissolved


## P39: true when `a` counts toward the music's combat (the music director's rule, decision 6): a
## special enemy (a boss, a rival giant, a formation member, an engine crew) or one at least
## `ratio` x the giant's height.
static func counts_for_music(a: EnemyActor, player_height_m: float, ratio: float) -> bool:
	var h := a.entity.combatant.height_m if a.entity != null and a.entity.combatant != null else 1.8
	return AudioMath.threat_counts(h, player_height_m, MusicDirector.is_special(a), ratio)


func _lesser_ratio() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var audio: Node = tree.root.get_node_or_null("Audio") if tree != null else null
	if audio != null and audio.get("mix") is Dictionary:
		var cfg: Variant = (audio.get("mix") as Dictionary).get("intensity", {})
		if cfg is Dictionary:
			return float((cfg as Dictionary).get("lesser_height_ratio", 0.3))
	return 0.3


## The music's intensity now ("off" while audio does not run).
func _music_key() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var audio: Node = tree.root.get_node_or_null("Audio") if tree != null else null
	if audio != null and bool(audio.get("enabled")) and audio.get("music") != null:
		var m: Object = audio.get("music")
		return str(m.get("intensity")) if "intensity" in m else "off"
	return "off"


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


## The current level's streamer counters: read live while the streamer is there, else the last
## snapshot (a death's reload frees the level before the next one is announced).
func _current_stream_stats() -> Dictionary:
	if _streamer_ref != null:
		var s := _streamer_ref.get_ref() as ChunkStreamer
		if s != null and is_instance_valid(s):
			_stream_snapshot = s.stats()
	return _stream_snapshot


## The counters of the level now ending, added to the run's (each load's streamer starts its own).
func _fold_streamer() -> void:
	var st := _current_stream_stats()
	if st.is_empty():
		return
	stream_totals.loads = int(stream_totals.loads) + int(st.get("loads", 0))
	stream_totals.unloads = int(stream_totals.unloads) + int(st.get("unloads", 0))
	stream_totals.thrash = int(stream_totals.thrash) + int(st.get("thrash", 0))
	stream_totals.work_ms_max = maxf(float(stream_totals.work_ms_max), float(st.get("work_ms_max", 0.0)))
	streaming = st
	_stream_snapshot = {}


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


## P39: the growth seconds with §6.4's shares (-1 when nothing was engaged): lone humans fleeing or
## routed, formations holding while their banner lives, and the music in combat among only lesser
## enemies.
func _growth_out() -> Dictionary:
	var out := {}
	for k: String in growth:
		out[k] = snappedf(float(growth[k]), 0.01)
	var lone := float(growth.lone_engaged_s)
	var held := float(growth.formation_engaged_s)
	var lesser := 0.0
	for k: String in music_lesser:
		lesser += float(music_lesser[k])
	out["lone_fled_share"] = snappedf(float(growth.lone_fled_s) / lone, 0.001) if lone > 0.0 else -1.0
	out["formation_held_share"] = snappedf(float(growth.formation_held_s) / held, 0.001) if held > 0.0 else -1.0
	out["lesser_s"] = snappedf(lesser, 0.01)
	out["lesser_combat_share"] = snappedf(float(music_lesser.get("combat", 0.0)) / lesser, 0.001) \
		if lesser > 0.0 and not music_lesser.has("off") else -1.0
	return out


func result() -> Dictionary:
	var cur := _current_stream_stats()
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
		"streaming": {"loads": int(stream_totals.loads) + int(cur.get("loads", 0)),
			"unloads": int(stream_totals.unloads) + int(cur.get("unloads", 0)),
			"thrash": int(stream_totals.thrash) + int(cur.get("thrash", 0)),
			"work_ms_max": maxf(float(stream_totals.work_ms_max), float(cur.get("work_ms_max", 0.0))), "min_margin_m": snappedf(min_margin_m, 0.1) if min_margin_m != INF else -1.0,
			"last": (cur if not cur.is_empty() else streaming).duplicate(true)},
		"path_queries_per_tick": {"p50": _query_percentile(0.5), "p95": _query_percentile(0.95), "max": q_max},
		"music": music.duplicate(true),
		"growth": _growth_out(),
		"music_lesser": music_lesser.duplicate(true),
		"lone_states": lone_states.duplicate(true),
		"save_bytes_max": save_bytes_max,
		"deaths_by_region": deaths_by_region.duplicate(),
		"refusals": refusals.duplicate(true),
	}
