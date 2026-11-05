class_name RunMetrics
extends RefCounted
## The Valley bot's per-run metrics (plan §5.1, decision 30): everything AUTOPILOT_RESULT reports
## about how a run played. It lives in a static of ValleyBot, so it survives the scene reloads of
## deaths and checkpoints; it listens to Events for what the game does and the bot reports what only
## it knows (its mode each tick, stuck events, dialogue it read, screens it would have opened).
##
## Accounting is per simulation tick (ValleyBot calls on_tick once per Sim tick):
##   * segments (§4.9) follow quest.main's current stage - SEGMENTS lists the stages of each; a
##     death reload that rolls the stage back counts the replay to that earlier segment;
##   * objectives are quest stages (every active quest's current stage, main and side), opened and
##     closed by polling the stage flags, so a rollback reopens the stage it returns to;
##   * the human estimate (§5.1): raw seconds + 4 s per dialogue node read + text length / 15
##     characters per second (dialogue and tutorial prompts) + 8 s per screen a player would open
##     (shrine rest or growth, forge, dialogue, inventory for attribute points, end) + 10 s per
##     district entered for the first time in the run;
##   * readability: a hit the giant takes is "off camera" when its attacker was outside the
##     camera's view when its windup began, and "late" when it landed less than 0.45 s after its
##     telegraph appeared;
##   * rewards: once-flags (reward.*) and loot by world id, rebuilt from the world state after every
##     load (a reward rolled back by a reload may be granted again); one granted while already in
##     the world state is a duplicate (an invariant failure).

const PLAYER_ID := "player"
const TICK_S := 1.0 / 60.0
## [segment id, quest.main stages] (plan §4.9).
const SEGMENTS := [
	["1_hollow", ["leave_hollow"]],
	["2_forest", ["wolves", "ogre"]],
	["3_grove", ["grove", "hurl"]],
	["4_village", ["to_village", "village"]],
	["5_ruins", ["bridge", "gate", "courtyard", "causeway"]],
	["6_boss", ["boss"]],
	["7_return", ["grow3", "tree", "deadfall", "crown"]],
]
const HUMAN_DIALOGUE_NODE_S := 4.0
const HUMAN_READ_CHARS_PER_S := 15.0
const HUMAN_SCREEN_S := 8.0
const HUMAN_DISTRICT_S := 10.0
const LATE_TELEGRAPH_TICKS := 27        ## 0.45 s
const SAMPLE_EVERY_TICKS := 6           ## AI-state histogram sampling
const NODE_SAMPLE_EVERY_TICKS := 3600   ## 60 s
const LOAD_SAMPLE_DELAY_TICKS := 300    ## node count 5 s after a level load
const HOSTILE_NEAR_M := 40.0
const CAMERA_FALLBACK_HALF_FOV_DEG := 55.0

var policy := ""
var skill := ""
var assist := false
var seed_value := 0
var started_tick := -1
var ended_tick := -1
var completed := false
var completed_tick := -1

var segments: Dictionary = {}           ## id -> record (see _new_segment)
var objectives: Dictionary = {}         ## "quest:stage" -> record
var objective_order: Array[String] = []
var deaths: Array = []
var damage_by_archetype: Dictionary = {}
var damage_by_action: Dictionary = {}
var hits_taken := 0
var off_camera_hits := 0
var late_telegraph_hits := 0
var ttk: Dictionary = {}                ## archetype -> stage -> [seconds...]
var engagement: Dictionary = {}         ## stage -> [sum_m, n]
var ai_states: Dictionary = {}          ## stage -> archetype -> state -> seconds
var ability_uses: Dictionary = {}
var damage_dealt_by_action: Dictionary = {}
var ready_windows: Dictionary = {}      ## ability id -> {"open": bool, "used": int, "unused": int}
var actions := {"light": 0, "heavy": 0, "blocks": 0, "parries": 0, "blocked_hits": 0, "dodges": 0,
	"evaded": 0, "grabs": 0, "throws": 0}
var xp_timeline: Array = []
var growth_ticks: Array = []
var stuck_events: Array = []
var rewards_granted: Array = []         ## [tick, id]
var duplicate_rewards: Array = []       ## [tick, id]
var max_active_enemies := 0
var max_debris := 0
var max_hostiles_near := 0
var node_samples: Array = []            ## [tick, nodes, orphans, static_mb]
var load_samples: Array = []            ## [tick, nodes outside Spawned, orphans] 5 s after each load
var xp_total := 0
var level := 1
var district_seen: Dictionary = {}
var dialogues: Array = []               ## [tick, dialogue id, outcome]
var notes: Array = []                   ## free-form bot notes [tick, text]

var _granted: Dictionary = {}           ## reward id -> tick (the current world timeline)
var _open_objective: Dictionary = {}    ## quest id -> objective key
var _windups: Dictionary = {}           ## actor id -> {"tick", "action_id", "on_camera", "telegraph"}
var _first_hit: Dictionary = {}         ## enemy id -> {"tick", "stage", "archetype"}
var _last_hit_taken: Dictionary = {}    ## {"attacker", "action_id", "tick"}
var _last_health_frac := 1.0
var _segment := ""
var _last_tick := -1
var _load_tick := -1
var _player: GiantPlayer = null
var _connected := false


func _init(options: Dictionary = {}) -> void:
	policy = str(options.get("policy", ""))
	skill = str(options.get("skill", "novice"))
	assist = bool(options.get("assist", false))
	seed_value = int(options.get("seed", 0))
	for s: Array in SEGMENTS:
		segments[s[0]] = _new_segment(str(s[0]), s[1])


static func _new_segment(id: String, stages: Array) -> Dictionary:
	return {"id": id, "stages": stages.duplicate(), "raw_s": 0.0, "combat_s": 0.0, "traversal_s": 0.0,
		"other_s": 0.0, "deaths": 0, "damage_taken": 0, "min_health_frac": 1.0, "checkpoints": [],
		"rests": 0, "free_rests": 0, "dialogue_nodes": 0, "text_chars": 0, "screens": 0,
		"new_districts": 0, "first_tick": -1, "last_tick": -1}


## The segment of a quest.main stage ("" when none lists it).
static func segment_of_stage(stage_id: String) -> String:
	for s: Array in SEGMENTS:
		if (s[1] as Array).has(stage_id):
			return str(s[0])
	return ""


# --------------------------------------------------------------------------- events

func connect_events() -> void:
	if _connected:
		return
	_connected = true
	for pair: Array in _listeners():
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
		[Events.hit_resolved, _on_hit_resolved],
		[Events.entity_died, _on_entity_died],
		[Events.ability_started, _on_ability_started],
		[Events.telegraph_started, _on_telegraph_started],
		[Events.grab_started, _on_grab_started],
		[Events.level_changed, _on_level_changed],
		[Events.xp_gained, _on_xp_gained],
		[Events.growth_changed, _on_growth_changed],
		[Events.flag_changed, _on_flag_changed],
		[Events.loot_awarded, _on_loot_awarded],
		[Events.checkpoint_reached, _on_checkpoint_reached],
		[Events.checkpoint_loaded, _on_checkpoint_loaded],
		[Events.shrine_rested, _on_shrine_rested],
		[Events.shrine_activated, _on_shrine_activated],
		[Events.tutorial_shown, _on_tutorial_shown],
		[Events.dialogue_outcome, _on_dialogue_outcome],
	]


func _on_hit_resolved(tick: int, r: HitResult) -> void:
	if r == null or r.event == null:
		return
	var ev := r.event
	if ev.target_id == PLAYER_ID:
		match r.outcome:
			HitResult.Outcome.PARRIED:
				actions.parries += 1
			HitResult.Outcome.BLOCKED:
				actions.blocked_hits += 1
			HitResult.Outcome.EVADED:
				actions.evaded += 1
		if r.health_damage > 0:
			_on_damage_taken(tick, ev, r.health_damage)
	elif ev.attacker_id == PLAYER_ID:
		if r.health_damage > 0:
			damage_dealt_by_action[ev.action_id] = int(damage_dealt_by_action.get(ev.action_id, 0)) + r.health_damage
			_credit_objectives("damage_dealt", r.health_damage)
			var e := Sim.get_entity(ev.target_id)
			if e != null and e.team == CombatEntity.Team.ENEMY and not _first_hit.has(ev.target_id):
				_first_hit[ev.target_id] = {"tick": tick, "stage": _stage(), "archetype": archetype_of(e)}


func _on_damage_taken(tick: int, ev: HitEvent, amount: int) -> void:
	var e := Sim.get_entity(ev.attacker_id)
	var arch := archetype_of(e) if e != null else "unknown"
	damage_by_archetype[arch] = int(damage_by_archetype.get(arch, 0)) + amount
	damage_by_action[ev.action_id] = int(damage_by_action.get(ev.action_id, 0)) + amount
	_last_hit_taken = {"attacker": ev.attacker_id, "action_id": ev.action_id, "tick": tick, "archetype": arch}
	hits_taken += 1
	var w: Dictionary = _windups.get(ev.attacker_id, {})
	if not w.is_empty():
		if not bool(w.get("on_camera", true)):
			off_camera_hits += 1
		if bool(w.get("telegraph", false)) and tick - int(w.tick) < LATE_TELEGRAPH_TICKS:
			late_telegraph_hits += 1
	var seg: Dictionary = segments.get(_segment, {})
	if not seg.is_empty():
		seg.damage_taken = int(seg.damage_taken) + amount
	_credit_objectives("damage_taken", amount)


func _on_entity_died(tick: int, entity_id: String, killer_id: String) -> void:
	if entity_id == PLAYER_ID:
		var killer := killer_id if killer_id != "" else str(_last_hit_taken.get("attacker", ""))
		var ke := Sim.get_entity(killer)
		var arch := archetype_of(ke) if ke != null else str(_last_hit_taken.get("archetype", "unknown"))
		deaths.append({"tick": tick, "segment": _segment, "objective": _main_objective_key(),
			"killer_id": killer, "killer_archetype": arch,
			"action_id": str(_last_hit_taken.get("action_id", "")) if str(_last_hit_taken.get("attacker", "")) == killer else ""})
		var seg: Dictionary = segments.get(_segment, {})
		if not seg.is_empty():
			seg.deaths = int(seg.deaths) + 1
		_credit_objectives("deaths", 1)
		return
	var first: Dictionary = _first_hit.get(entity_id, {})
	if not first.is_empty():
		_first_hit.erase(entity_id)
		var arch := str(first.archetype)
		var by_stage: Dictionary = ttk.get(arch, {})
		var key := str(first.stage)
		var list: Array = by_stage.get(key, [])
		list.append(snappedf(float(tick - int(first.tick)) * TICK_S, 0.01))
		by_stage[key] = list
		ttk[arch] = by_stage


func _on_ability_started(tick: int, actor_id: String, action_id: String, _instance: int) -> void:
	if actor_id == PLAYER_ID:
		var a := GameData.get_action(action_id)
		var kind := a.kind if a != null else ""
		match kind:
			"light":
				actions.light += 1
			"heavy":
				actions.heavy += 1
			"dodge":
				actions.dodges += 1
			"block":
				actions.blocks += 1
			"ability", "ultimate":
				if action_id == PlayerGrab.THROW_ID:
					actions.throws += 1
				elif action_id != PlayerGrab.GRAB_ID:
					ability_uses[action_id] = int(ability_uses.get(action_id, 0)) + 1
					var w: Dictionary = ready_windows.get(action_id, {})
					if bool(w.get("open", false)):
						w.open = false
						w.used = int(w.get("used", 0)) + 1
		return
	var e := Sim.get_entity(actor_id)
	if e == null or e.team == CombatEntity.Team.PLAYER:
		return
	_windups[actor_id] = {"tick": tick, "action_id": action_id, "on_camera": on_camera(e), "telegraph": false}


func _on_telegraph_started(tick: int, actor_id: String, action_id: String, target_id: String,
		_shape: String, _origin: Vector3, _yaw: float, _radius: float, _length: float, _duration_s: float) -> void:
	if target_id != PLAYER_ID:
		return
	var w: Dictionary = _windups.get(actor_id, {})
	if w.is_empty() or int(w.tick) != tick:
		var e := Sim.get_entity(actor_id)
		w = {"tick": tick, "action_id": action_id, "on_camera": on_camera(e) if e != null else true}
		_windups[actor_id] = w
	w["telegraph"] = true


func _on_grab_started(_tick: int, holder_id: String, _target_id: String) -> void:
	if holder_id == PLAYER_ID:
		actions.grabs += 1


func _on_level_changed(tick: int, _old_level: int, new_level: int) -> void:
	level = new_level
	xp_timeline.append([tick, new_level, xp_total])


func _on_xp_gained(_tick: int, _amount: int, _source: String, total: int) -> void:
	xp_total = total


func _on_growth_changed(tick: int, entity_id: String, _old: int, new_stage: int) -> void:
	if entity_id == PLAYER_ID:
		growth_ticks.append([tick, new_stage])


func _on_flag_changed(tick: int, flag_id: String, value: Variant) -> void:
	if flag_id.begins_with("reward.") and QuestConditions.truthy(value):
		_grant(tick, flag_id)


func _on_loot_awarded(tick: int, world_id: String, _item_id: String, _count: int, _recipient: String) -> void:
	var key := "loot:" + world_id
	# One award event per item of a loot table: a second item of the same award is not a duplicate.
	if int(_granted.get(key, -1)) == tick:
		return
	_grant(tick, key)


func _grant(tick: int, id: String) -> void:
	if _granted.has(id):
		duplicate_rewards.append([tick, id])
	_granted[id] = tick
	rewards_granted.append([tick, id])


## The rewards present in the world state now (after a load): once-flags and loot already given.
func rebuild_granted() -> void:
	_granted.clear()
	for f: String in WorldState.flags:
		if f.begins_with("reward.") and QuestConditions.truthy(WorldState.flags[f]):
			_granted[f] = -1
	for id: String in WorldState.deltas:
		var d: Variant = WorldState.deltas[id]
		if typeof(d) == TYPE_DICTIONARY and (bool(d.get("loot_awarded", false)) or bool(d.get("killed", false))):
			_granted["loot:" + id] = -1


func _on_checkpoint_reached(tick: int, checkpoint_id: String, kind: String) -> void:
	var seg: Dictionary = segments.get(_segment, {})
	if not seg.is_empty():
		(seg.checkpoints as Array).append({"tick": tick, "id": checkpoint_id, "kind": kind,
			"health_frac": snappedf(_last_health_frac, 0.001)})


func _on_checkpoint_loaded(_tick: int, _checkpoint_id: String, _source: String) -> void:
	rebuild_granted()
	_windups.clear()
	_first_hit.clear()


func _on_shrine_rested(_tick: int, _shrine_id: String) -> void:
	_add_segment("rests", 1)


func _on_shrine_activated(_tick: int, _shrine_id: String) -> void:
	_add_segment("free_rests", 1)


func _on_tutorial_shown(_tick: int, prompt_id: String) -> void:
	var text := str(Quests.current_tutorial().get("text", ""))
	if text == "":
		text = str(GameData.get_record(prompt_id).get("text", ""))
	_add_segment("text_chars", text.length())


func _on_dialogue_outcome(tick: int, dialogue_id: String, outcome: String) -> void:
	dialogues.append([tick, dialogue_id, outcome])


# --------------------------------------------------------------------------- bot reports

## A new game (New Game, or the loop's next run): the world is empty again.
func on_new_game(tick: int) -> void:
	if started_tick < 0:
		started_tick = tick
	rebuild_granted()


## A level (re)load: the node count is sampled LOAD_SAMPLE_DELAY_TICKS later.
func note_level_loaded(tick: int) -> void:
	_load_tick = tick
	_windups.clear()


## A node the bot read in a conversation (its text), or a choice it made.
func note_dialogue_text(text: String, node := true) -> void:
	if node:
		_add_segment("dialogue_nodes", 1)
	_add_segment("text_chars", text.length())


## A screen a human would have opened (shrine, forge, dialogue, inventory, end).
func note_screen(_kind: String) -> void:
	_add_segment("screens", 1)


func note_stuck(tick: int, position: Vector3, objective: String, recovered_by: String) -> void:
	stuck_events.append({"tick": tick, "position": [snappedf(position.x, 0.1), snappedf(position.y, 0.1),
		snappedf(position.z, 0.1)], "objective": objective, "recovered_by": recovered_by})


func note(tick: int, text: String) -> void:
	notes.append([tick, text])
	if notes.size() > 200:
		notes.remove_at(0)


## Combat readiness of the slotted abilities this tick (the "used when ready" ratio): an ability
## that becomes ready during combat opens a window; its use closes it as used, losing readiness or
## the end of the fight as unused.
func note_readiness(ready: Dictionary, in_combat: bool) -> void:
	for id: String in ready:
		var w: Dictionary = ready_windows.get(id, {"open": false, "used": 0, "unused": 0})
		ready_windows[id] = w
		var now_ready := bool(ready[id]) and in_combat
		if now_ready and not bool(w.open):
			w.open = true
		elif not now_ready and bool(w.open):
			w.open = false
			w.unused = int(w.unused) + 1


func note_engagement(distance_m: float) -> void:
	var key := str(_stage())
	var e: Array = engagement.get(key, [0.0, 0])
	e[0] = float(e[0]) + distance_m
	e[1] = int(e[1]) + 1
	engagement[key] = e


# --------------------------------------------------------------------------- per tick

## Once per simulation tick. mode: "combat" | "traverse" | "other".
func on_tick(tick: int, player: GiantPlayer, level_root: LevelRoot, mode: String) -> void:
	if tick == _last_tick:
		return
	_last_tick = tick
	_player = player
	if started_tick < 0:
		started_tick = tick
	ended_tick = tick
	var main_stage := Quests.stage_of(Quests.MAIN_QUEST_ID)
	_segment = "" if Quests.is_complete(Quests.MAIN_QUEST_ID) else segment_of_stage(main_stage)
	var seg: Dictionary = segments.get(_segment, {})
	if not seg.is_empty():
		seg.raw_s = float(seg.raw_s) + TICK_S
		var key := "combat_s" if mode == "combat" else ("traversal_s" if mode == "traverse" else "other_s")
		seg[key] = float(seg[key]) + TICK_S
		if int(seg.first_tick) < 0:
			seg.first_tick = tick
		seg.last_tick = tick
	_sync_objectives(tick)
	if player != null and is_instance_valid(player) and player.entity != null:
		var pools := player.entity.combatant.pools
		_last_health_frac = pools.health / maxf(1.0, pools.health_max)
		if not seg.is_empty() and player.entity.is_alive():
			seg.min_health_frac = minf(float(seg.min_health_frac), _last_health_frac)
		if level_root != null and is_instance_valid(level_root):
			var district := level_root.district_at(player.global_position)
			if district != "" and not district_seen.has(district):
				district_seen[district] = tick
				_add_segment("new_districts", 1)
	if level_root != null and is_instance_valid(level_root):
		var d := level_root.director()
		if d != null:
			max_active_enemies = maxi(max_active_enemies, d.active_combatant_count())
	var tree := player.get_tree() if player != null and is_instance_valid(player) and player.is_inside_tree() else null
	if tree != null:
		var pool := tree.get_first_node_in_group("debris_pool") as DebrisPool
		if pool != null:
			max_debris = maxi(max_debris, pool.active_count())
		if tick % SAMPLE_EVERY_TICKS == 0:
			_sample_ai_states(tree, player)
		if tick % NODE_SAMPLE_EVERY_TICKS == 0:
			node_samples.append([tick, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
				snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)])
		if _load_tick >= 0 and tick - _load_tick >= LOAD_SAMPLE_DELAY_TICKS:
			_load_tick = -1
			var spawned := 0
			if level_root != null and is_instance_valid(level_root):
				var sp := level_root.get_node_or_null("Spawned")
				if sp != null:
					spawned = _count_nodes(sp)
			load_samples.append([tick, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - spawned,
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])


static func _count_nodes(n: Node) -> int:
	var c := 1
	for child in n.get_children():
		c += _count_nodes(child)
	return c


## Enemies engaged with the giant (aware, alive, within HOSTILE_NEAR_M) add SAMPLE_EVERY_TICKS
## ticks to their archetype's state (and outmatched behaviour) at the giant's stage.
func _sample_ai_states(tree: SceneTree, player: GiantPlayer) -> void:
	var stage_key := str(_stage())
	var hostiles := 0
	for n in tree.get_nodes_in_group("enemies"):
		var a := n as EnemyActor
		if a == null or not a.is_inside_tree() or a.entity == null or not a.entity.is_alive() or a.brain == null:
			continue
		if a.global_position.distance_to(player.global_position) > HOSTILE_NEAR_M or not a.brain.aware:
			continue
		if a.entity.team == CombatEntity.Team.ENEMY:
			hostiles += 1
		var arch := archetype_of(a.entity)
		var by_stage: Dictionary = ai_states.get(stage_key, {})
		var by_arch: Dictionary = by_stage.get(arch, {})
		var dt := float(SAMPLE_EVERY_TICKS) * TICK_S
		var state := a.brain.state_name()
		by_arch[state] = snappedf(float(by_arch.get(state, 0.0)) + dt, 0.001)
		if a.brain.is_outmatched():
			var key := "behavior:" + a.brain.outmatched_behavior()
			by_arch[key] = snappedf(float(by_arch.get(key, 0.0)) + dt, 0.001)
		by_arch["engaged"] = snappedf(float(by_arch.get("engaged", 0.0)) + dt, 0.001)
		by_stage[arch] = by_arch
		ai_states[stage_key] = by_stage
	max_hostiles_near = maxi(max_hostiles_near, hostiles)


## Keeps one open objective per active quest (its current stage); closes the stages that changed.
func _sync_objectives(tick: int) -> void:
	var active := {}
	for qid in Quests.active_quest_ids():
		active[qid] = true
		var key := "%s:%s" % [qid, Quests.stage_of(qid)]
		if str(_open_objective.get(qid, "")) == key:
			continue
		_close_objective(qid, tick)
		var rec: Dictionary = objectives.get(key, {})
		if rec.is_empty():
			rec = {"id": key, "start_tick": tick, "end_tick": -1, "seconds": 0.0, "deaths": 0,
				"damage_taken": 0, "damage_dealt": 0, "visits": 0}
			objectives[key] = rec
			objective_order.append(key)
		rec.visits = int(rec.visits) + 1
		rec["open_since"] = tick
		_open_objective[qid] = key
	for qid: String in _open_objective.keys():
		if not active.has(qid):
			_close_objective(qid, tick)


func _close_objective(qid: String, tick: int) -> void:
	var key := str(_open_objective.get(qid, ""))
	if key == "":
		return
	_open_objective.erase(qid)
	var rec: Dictionary = objectives.get(key, {})
	if rec.is_empty():
		return
	rec.seconds = snappedf(float(rec.seconds) + float(tick - int(rec.get("open_since", tick))) * TICK_S, 0.01)
	rec.end_tick = tick
	rec.erase("open_since")


func _credit_objectives(field: String, amount: int) -> void:
	for qid: String in _open_objective:
		var rec: Dictionary = objectives.get(str(_open_objective[qid]), {})
		if not rec.is_empty():
			rec[field] = int(rec.get(field, 0)) + amount


func _main_objective_key() -> String:
	return str(_open_objective.get(Quests.MAIN_QUEST_ID, ""))


## Adds to the current segment's counter (before the first tick: the first segment; after the
## slice: the last one, e.g. the end screen).
func _add_segment(field: String, amount: int) -> void:
	var id := _segment
	if id == "":
		id = str(SEGMENTS[SEGMENTS.size() - 1][0]) if completed else str(SEGMENTS[0][0])
	var seg: Dictionary = segments.get(id, {})
	if not seg.is_empty():
		seg[field] = int(seg.get(field, 0)) + amount


func _stage() -> int:
	return _player.current_growth_stage() if _player != null and is_instance_valid(_player) else 1


func mark_completed(tick: int) -> void:
	if completed:
		return
	completed = true
	completed_tick = tick


# --------------------------------------------------------------------------- helpers

static func archetype_of(e: CombatEntity) -> String:
	if e == null or e.combatant == null:
		return "unknown"
	var a := str(e.combatant.base_record.get("archetype", ""))
	if a == "":
		a = str(e.combatant.base_record.get("role", ""))
	return a if a != "" else e.definition_id


## True when `e`'s actor is in front of the giant's camera, inside its horizontal field of view.
func on_camera(e: CombatEntity) -> bool:
	if e == null or e.actor == null or _player == null or not is_instance_valid(_player):
		return true
	var rig := _player.camera_rig
	if rig == null or rig.camera == null or not rig.camera.is_inside_tree():
		return true
	var cam := rig.camera
	var to := (e.actor as Node3D).global_position - cam.global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return true
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return true
	var half := deg_to_rad(CAMERA_FALLBACK_HALF_FOV_DEG)
	if cam.fov > 1.0:
		var aspect := 16.0 / 9.0
		var vp := cam.get_viewport()
		if vp != null:
			var size := vp.get_visible_rect().size
			if size.y > 1.0:
				aspect = size.x / size.y
		half = atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect)
	return absf(fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)) <= half


static func _mean(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var s := 0.0
	for v: Variant in list:
		s += float(v)
	return s / float(list.size())


func human_extra_s(seg: Dictionary) -> float:
	return HUMAN_DIALOGUE_NODE_S * float(seg.dialogue_nodes) + float(seg.text_chars) / HUMAN_READ_CHARS_PER_S \
		+ HUMAN_SCREEN_S * float(seg.screens) + HUMAN_DISTRICT_S * float(seg.new_districts)


# --------------------------------------------------------------------------- the result

## Closes what is still open and returns the metrics part of AUTOPILOT_RESULT.
func result(tick: int) -> Dictionary:
	for qid: String in _open_objective.keys():
		_close_objective(qid, tick)
	for id: String in ready_windows:
		var w: Dictionary = ready_windows[id]
		if bool(w.open):
			w.open = false
			w.unused = int(w.unused) + 1
	var seg_out: Array = []
	var raw_total := 0.0
	var human_total := 0.0
	for s: Array in SEGMENTS:
		var seg: Dictionary = segments[s[0]]
		var human := float(seg.raw_s) + human_extra_s(seg)
		raw_total += float(seg.raw_s)
		human_total += human
		seg_out.append({"id": seg.id, "stages": seg.stages, "raw_s": snappedf(float(seg.raw_s), 0.01),
			"human_estimate_s": snappedf(human, 0.01), "combat_s": snappedf(float(seg.combat_s), 0.01),
			"traversal_s": snappedf(float(seg.traversal_s), 0.01), "other_s": snappedf(float(seg.other_s), 0.01),
			"deaths": seg.deaths, "damage_taken": seg.damage_taken,
			"min_health_frac": snappedf(float(seg.min_health_frac), 0.001), "checkpoints": seg.checkpoints,
			"rests": seg.rests, "free_rests": seg.free_rests, "dialogue_nodes": seg.dialogue_nodes,
			"text_chars": seg.text_chars, "screens": seg.screens, "new_districts": seg.new_districts})
	var obj_out: Array = []
	for key in objective_order:
		var rec: Dictionary = objectives[key]
		obj_out.append({"id": rec.id, "start_tick": rec.start_tick, "end_tick": rec.end_tick,
			"seconds": rec.seconds, "visits": rec.visits, "deaths": rec.deaths,
			"damage_taken": rec.damage_taken, "damage_dealt": rec.damage_dealt})
	var ttk_out := {}
	for arch: String in ttk:
		var by_stage := {}
		for st: String in ttk[arch]:
			var list: Array = ttk[arch][st]
			by_stage[st] = {"n": list.size(), "mean_s": snappedf(_mean(list), 0.01)}
		ttk_out[arch] = by_stage
	var eng_out := {}
	for st: String in engagement:
		var e: Array = engagement[st]
		eng_out[st] = {"n": int(e[1]), "mean_m": snappedf(float(e[0]) / maxf(1.0, float(e[1])), 0.01)}
	var ability_damage := 0
	for id: String in damage_dealt_by_action:
		var a := GameData.get_action(id)
		if a != null and a.kind in ["ability", "ultimate"] and id != PlayerGrab.THROW_ID:
			ability_damage += int(damage_dealt_by_action[id])
	var share := {}
	for id: String in damage_dealt_by_action:
		var a := GameData.get_action(id)
		if a != null and a.kind in ["ability", "ultimate"] and id != PlayerGrab.THROW_ID:
			share[id] = snappedf(float(damage_dealt_by_action[id]) / maxf(1.0, float(ability_damage)), 0.001)
	var ready := {}
	for id: String in ready_windows:
		var w: Dictionary = ready_windows[id]
		var total := int(w.used) + int(w.unused)
		ready[id] = {"used": int(w.used), "windows": total,
			"ratio": snappedf(float(w.used) / float(total), 0.001) if total > 0 else 0.0}
	return {
		"simulated_s": snappedf(float(maxi(0, tick - started_tick)) * TICK_S, 0.01),
		"segment_raw_s": snappedf(raw_total, 0.01),
		"human_estimate_s": snappedf(human_total, 0.01),
		"completed": completed,
		"completed_s": snappedf(float(completed_tick - started_tick) * TICK_S, 0.01) if completed else -1.0,
		"village_outcome": str(WorldState.get_flag("quest.village.outcome", "")),
		"flags_hash": flags_hash(),
		"segments": seg_out,
		"objectives": obj_out,
		"deaths": deaths.duplicate(true),
		"damage_taken_by_archetype": damage_by_archetype.duplicate(),
		"damage_taken_by_action": damage_by_action.duplicate(),
		"readability": {"hits_taken": hits_taken, "off_camera": off_camera_hits,
			"late_telegraph": late_telegraph_hits,
			"off_camera_share": snappedf(float(off_camera_hits) / maxf(1.0, float(hits_taken)), 0.001),
			"late_telegraph_share": snappedf(float(late_telegraph_hits) / maxf(1.0, float(hits_taken)), 0.001)},
		"ttk": ttk_out,
		"engagement_distance": eng_out,
		"ai_states": ai_states.duplicate(true),
		"abilities": {"uses": ability_uses.duplicate(), "damage": damage_dealt_by_action.duplicate(),
			"damage_share": share, "used_when_ready": ready},
		"actions": actions.duplicate(),
		"xp_timeline": xp_timeline.duplicate(true),
		"xp": xp_total,
		"level": level,
		"growth_ticks": growth_ticks.duplicate(true),
		"stuck_events": stuck_events.duplicate(true),
		"rewards": {"granted": rewards_granted.duplicate(true), "duplicates": duplicate_rewards.duplicate(true)},
		"max_active_enemies": max_active_enemies,
		"max_debris": max_debris,
		"max_hostiles_near": max_hostiles_near,
		"nodes": node_samples.duplicate(true),
		"load_nodes": load_samples.duplicate(true),
		"districts": district_seen.keys(),
		"dialogues": dialogues.duplicate(true),
	}


## A hash of the world flags (sorted), to compare runs.
static func flags_hash() -> String:
	var keys := WorldState.flags.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k: Variant in keys:
		parts.append("%s=%s" % [k, WorldState.flags[k]])
	return ";".join(parts).md5_text().substr(0, 12)
