class_name ValleyBot
extends Node
## The Valley bot (plan §3.19, §5.1-5.2, decision 30): a goal-driven player that plays the whole
## quest line of the Valley under a village policy (help_cache | help_ogre | intimidate | force),
## with a novice or expert skill profile (BotCombat) and an optional assisted mode (the hidden
## status.bot_assist: damage taken x0.25), measures how it plays (RunMetrics), checks the stability
## invariants every tick and diagnoses a breach (BotDiagnosis).
##
## The Autopilot dispatches it for --scenario=valley (with --mode=valley --new-game) and makes one
## node per level load; the run's state lives in the static `run`, so it survives the scene
## reloads of deaths, checkpoint loads and new games. The node runs PROCESS_MODE_ALWAYS: a pausing
## screen would freeze a pausable bot, so it closes any pausing screen it finds (after recording it)
## and calls the screen-backed APIs directly instead of opening screens: Quests.start_dialogue +
## the session's choose_outcome, shrine.rest / shrine.grow, forge.upgrade, progression.allocate,
## equipment.equip_weapon. Pickups, racks and the oak use the real interact edge; everything else
## goes through the input router (stick, edges, holds) and the camera, as a player's input would.
##
## Every 6 ticks it reads the objectives (Quests) and picks a task; every tick it carries the task
## out. In order: a fight when aware hostile enemies are near (BotCombat; elevated or unreachable
## ones are left alone), the Hollow's optional tutorial (bounded by TUTORIAL_BUDGET_S), errands
## (rest when hurt or before the boss, reforge at an open forge with two iron, the armory's sword
## and crate, the quarry chest; each given up after ERRAND_GIVE_UP_S), the village policy at the
## `village` stage, else quest.main's stage `bot` hint: go | fight_encounter | kill | grow |
## hurl_at | break | interact | talk (a hurt giant rests before a kill).
##
## Movement follows a navigation path on the giant's current layers (NavQuery.path with
## player.nav_layers, P24b: the Valley's map_get_path parameters), re-planned every REPATH_S or when
## the giant strays OFF_PATH_M off it.
## Stuck (the distance to the goal has not dropped by STUCK_PROGRESS_M in STUCK_S while
## traversing): sidestep and jump, then re-plan (or, when no path leads on from where the giant
## stands but one does from where it was - a pocket of the navmesh it walked into while fighting -
## a walk back along its breadcrumbs), then the bot_route_points fallback, then a teleport to the
## next path point (recorded); one more is a breach.
##
## Watchdogs: OBJECTIVE_TIMEOUT_S per quest.main stage (BOSS_TIMEOUT_S for the boss), at most
## MAX_DEATHS_PER_OBJECTIVE deaths on one stage (unassisted runs), and stuck. A breach runs
## BotDiagnosis.diagnose: a single run then ends (Autopilot exit code 2); a loop run records it,
## reloads the last checkpoint and goes on. Deaths: the bot waits for the death screen to accept
## its confirm, then emits reload_checkpoint_requested("death") as Enter does, and re-applies the
## assist status after every load.
##
## --bot-loop (the 30-minute stability run): after the slice is complete the bot starts a new game
## with the next village policy in POLICIES (rotation) and goes on until --autoplay ends; every run
## is summarised in `loop_runs`.

const GROUP := "valley_bot"
const POLICIES := ["help_cache", "help_ogre", "intimidate", "force"]
const SKILLS := ["novice", "expert"]
const ASSIST_STATUS := "status.bot_assist"
const ASSIST_RENEW_S := 60.0
const MAIN := "quest.main"
const TUTORIAL := "quest.tutorial"
const PLAN_EVERY_TICKS := 6
const REPATH_S := 2.0
const OFF_PATH_M := 3.0
const WAYPOINT_M := 1.3
const STUCK_S := 6.0
const STUCK_PROGRESS_M := 1.0
const OBJECTIVE_TIMEOUT_S := 240.0
const BOSS_TIMEOUT_S := 480.0
const MAX_DEATHS_PER_OBJECTIVE := 5
const DEATH_WAIT_S := 1.5
const TUTORIAL_BUDGET_S := 120.0
const SCREEN_CLOSE_AFTER_S := 0.25
const REST_BELOW_HEALTH := 0.45
const KILL_REST_BELOW_HEALTH := 0.5
const KILL_REST_RADIUS_M := 250.0
const ERRAND_RADIUS_M := 70.0
const ERRAND_GIVE_UP_S := 45.0
const GAVE_UP := 1 << 30
const BREAK_SWINGS_PER_STEP := 3
const BREAK_STEP_M := 0.8
const CRUMB_EVERY_TICKS := 30
const CRUMB_SPACING_M := 1.5
const CRUMBS_KEPT := 48
const RETRACE_S := 12.0
## How long the bot stands at an encounter whose living members are all out of its reach (fleeing,
## elevated, unreachable) before it takes the stage's other way on (P17b).
const STALL_WALK_ON_S := 8.0
## The stall's wait starts this close to an encounter's centre and lasts while the giant stays within
## STALL_KEEP_M of it (M6 gate).
const STALL_START_M := 6.0
const STALL_KEEP_M := 15.0
## A fight that has taken no health off its target for CHASE_GIVE_UP_S (a stage-3 giant chasing a
## harassing wolf that keeps out of reach) is given up: the bot leaves that enemy alone for
## CHASE_IGNORE_S and goes on with its objective, as a person would stop chasing (P17b). Long enough
## to give up on two such wolves in turn and still reach the objective (with 30 s the barrow's two
## wolves took turns until the crown stage's watchdog).
const CHASE_GIVE_UP_S := 20.0
const CHASE_IGNORE_S := 90.0
const ELDER := "valley.village.elder"
const ELDER_DIALOGUE := "dialogue.elder"
const BARRICADE := "valley.village.barricade"
const CACHE := "valley.quarry.cache"
const FIELD_OGRE := "valley.fields.ogre"
const KINGSFALL_SHRINE := "valley.shrine.kingsfall"
const IRON := "item.iron_ingot"
const WEAPON_ORDER := ["weapon.club_reinforced", "weapon.sword_reinforced", "weapon.hammer_reinforced",
	"weapon.sword", "weapon.club", "weapon.hammer"]
const TREE_WEAPON := "weapon.tree_oak"


## The run: options, metrics and everything that must outlive a scene reload.
class Run extends RefCounted:
	var options: Dictionary = {}
	var policy := "help_cache"
	var skill := "novice"
	var assist := false
	var loop := false
	var seed_value := 0
	var trace_ticks := 0
	var rng: RandomNumberGenerator
	var metrics: RunMetrics
	var finished := false
	var finish_reason := ""
	var breaches: Array = []
	var invariant_failures: Array = []
	var dup_seen := 0
	var node_growth := ""
	var obj_key := ""
	var obj_ticks := 0
	var obj_deaths := 0
	var stuck_level := 0
	var death_tick := -1
	var reload_sent := false
	var tutorial_ticks := 0
	var allocate_flip := 0
	var loop_runs: Array = []
	var run_index := 0
	var rested_for_boss := false
	var screens_closed: Array = []
	var level_loads := 0
	var teleports := 0
	var started_tick := -1
	var completed_runs := 0
	## P38: the world bot's own state (WorldBot.WorldRun) when the run plays the world or the whole
	## campaign (--scenario=world, or --scenario=valley --bot-campaign); null for a Valley run.
	var world: RefCounted = null


static var run: Run = null

var player: GiantPlayer
var level: LevelRoot
var director: EncounterDirector
var combat: BotCombat
var task: Dictionary = {}
var mode := "other"
var _stall_since := -1   ## the tick an encounter task first found nothing to reach; -1 when it did
var _chase := {"id": "", "health": 0.0, "since": -1}   ## the fight being watched for progress
var _ignored := {}       ## entity id -> the tick until which the bot leaves that enemy alone

## The run's metrics (BotCombat reads them through the bot).
var metrics: RunMetrics:
	get:
		return run.metrics if run != null else null

var _bound_player_id := 0
var _last_tick := -1
var _next_plan_tick := 0
var _path := PackedVector3Array()
var _path_goal := Vector3.INF
var _path_index := 0
var _repath_tick := 0
var _stuck_best := INF
var _stuck_since := 0
var _stuck_goal := Vector3.INF
var _unstick_until := -1
var _unstick_dir := Vector3.ZERO
var _route_goal := Vector3.INF
var _talked_tick := -1000
var _interact_tick := -1000
var _camera_toggles := 0
var _tutorial_step_tick := 0
var _spar_instance := -1
var _spar_lead := 10
var _screen_seen_ms := -1
var _reach_cache: Dictionary = {}
var _last_steer_tick := -1
var _break_id := 0              ## the prop being broken (instance id)
var _break_health := -1.0       ## its health when a blow last landed (or when the task began)
var _break_swings := 0          ## blows since its health last dropped
var _break_swing_tick := -1000
var _break_closer := 0.0        ## metres closer than the reach suggests (blows that did not land)
var _errand_ticks: Dictionary = {}   ## errand -> ticks spent on it (this level load)
var _crumbs := PackedVector3Array()   ## where the giant has been (every CRUMB_SPACING_M, newest last)
var _retrace := PackedVector3Array()  ## breadcrumbs to walk back through, next first
var _retrace_until := -1


## Starts a run (once per process; later calls keep the running one). options: "policy", "skill",
## "assist", "loop", "seed".
static func configure(options: Dictionary) -> Run:
	if run != null:
		return run
	run = Run.new()
	run.options = options.duplicate()
	run.policy = str(options.get("policy", "help_cache"))
	if not (run.policy in POLICIES):
		run.policy = "help_cache"
	run.skill = str(options.get("skill", "novice"))
	if not (run.skill in SKILLS):
		run.skill = "novice"
	run.assist = bool(options.get("assist", false))
	run.loop = bool(options.get("loop", false))
	run.seed_value = int(options.get("seed", 0))
	run.trace_ticks = ActionDef.seconds_to_ticks(float(options.get("trace_s", 0.0))) if float(options.get("trace_s", 0.0)) > 0.0 else 0
	run.rng = Sim.rng_for("bot")
	run.rng.seed = hash("bot:%d" % run.seed_value)
	run.metrics = _new_metrics()
	run.metrics.connect_events()
	return run


static func _new_metrics() -> RunMetrics:
	return RunMetrics.new({"policy": run.policy, "skill": run.skill, "assist": run.assist, "seed": run.seed_value})


## Forgets the run (tests).
static func reset() -> void:
	if run != null and run.metrics != null:
		run.metrics.disconnect_events()
	run = null


## Parses the bot's command-line options: --bot-village=, --bot-skill=, --bot-assist, --bot-loop,
## --bot-seed=. Unknown values fall back to the defaults (help_cache, novice) with a warning.
static func parse_options(args: PackedStringArray) -> Dictionary:
	var out := {"policy": "help_cache", "skill": "novice", "assist": false, "loop": false, "seed": 0}
	for arg in args:
		if arg.begins_with("--bot-village="):
			var p := arg.substr(14).strip_edges().to_lower()
			if p in POLICIES:
				out.policy = p
			else:
				push_warning("ValleyBot: unknown --bot-village=%s (help_cache | help_ogre | intimidate | force)" % p)
		elif arg.begins_with("--bot-skill="):
			var s := arg.substr(12).strip_edges().to_lower()
			if s in SKILLS:
				out.skill = s
			else:
				push_warning("ValleyBot: unknown --bot-skill=%s (novice | expert)" % s)
		elif arg == "--bot-assist":
			out.assist = true
		elif arg == "--bot-loop":
			out.loop = true
		elif arg.begins_with("--bot-seed="):
			out.seed = int(arg.substr(11))
		elif arg.begins_with("--bot-trace="):
			out.trace_s = float(arg.substr(12))
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100   # after Sim (-1000) and the actors: read the tick, then act
	add_to_group(GROUP)


func _exit_tree() -> void:
	if combat != null:
		combat.teardown()
		combat = null


# --------------------------------------------------------------------------- binding

## Finds the level and its giant; a new giant (a load) resets the per-level state.
func _bind() -> bool:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	if p == null or not p.is_inside_tree():
		return false
	if p.get_instance_id() != _bound_player_id:
		_bound_player_id = p.get_instance_id()
		player = p
		level = get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot
		director = level.director() if level != null else null
		_on_level_loaded()
	return level != null


func _on_level_loaded() -> void:
	player.router.use_injection = true
	if combat != null:
		combat.teardown()
	combat = BotCombat.new()
	combat.setup(self, player, run.skill, run.rng)
	run.level_loads += 1
	run.reload_sent = false
	run.death_tick = -1
	run.stuck_level = 0
	_path = PackedVector3Array()
	_path_goal = Vector3.INF
	_stuck_best = INF
	_reach_cache.clear()
	run.metrics.note_level_loaded(Sim.tick)
	run.metrics.rebuild_granted()
	run.rested_for_boss = false
	if run.started_tick < 0:
		run.started_tick = Sim.tick
		run.metrics.on_new_game(Sim.tick)
	_keep_assist(true)


# --------------------------------------------------------------------------- the tick

func _physics_process(_delta: float) -> void:
	if run == null or run.finished:
		return
	if not _bind():
		return
	_handle_screens()
	if get_tree().paused:
		return
	var tick := Sim.tick
	if tick == _last_tick:
		return
	_last_tick = tick
	run.metrics.on_tick(tick, player, level, mode)
	_check_invariants(tick)
	if run.finished:
		return
	if player.controller.state == CombatController.State.DEAD:
		_handle_death(tick)
		return
	run.death_tick = -1
	_keep_assist(false)
	_allocate_points()
	if _slice_done():
		_on_slice_complete(tick)
		return
	var defending := combat.defend(tick)
	if tick % PLAN_EVERY_TICKS == 0:
		run.metrics.note_readiness(combat.readiness(), mode == "combat")
	if tick >= _next_plan_tick:
		_next_plan_tick = tick + PLAN_EVERY_TICKS
		_plan(tick)
	_act(tick, defending)
	_note_crumb(tick)
	_watchdogs(tick)
	if run.trace_ticks > 0 and tick % run.trace_ticks == 0:
		print(trace_line(tick))


func _slice_done() -> bool:
	return Quests.is_complete(MAIN) or QuestConditions.truthy(WorldState.get_flag("slice.completed", false))


# --------------------------------------------------------------------------- screens

## Pausing screens: the end screen when the slice completes, a shrine screen the interact edge opened
## by accident, ... The bot closes any of them after SCREEN_CLOSE_AFTER_S (real time) and notes it.
func _handle_screens() -> void:
	var open := false
	var open_s := 0.0
	var names := PackedStringArray()
	for n in get_tree().get_nodes_in_group(ScreenStack.GROUP):
		var s := n as ScreenStack
		if s != null and s.any_open():
			open = true
			open_s = maxf(open_s, s.open_seconds())
			var t := s.top()
			if t != null and t.get_script() != null:
				names.append(str(t.get_script().resource_path.get_file().get_basename()))
	if not open:
		_screen_seen_ms = -1
		return
	# The invariant (plan §5.2) is checked here too: while a screen pauses the game no tick runs.
	if open_s > BotDiagnosis.MAX_SCREEN_OPEN_S:
		run.invariant_failures.append({"tick": Sim.tick, "failure": "a pausing screen (%s) has been open %.1f s" % [
			",".join(names), open_s]})
		_finish("invariant")
		return
	if _screen_seen_ms < 0:
		_screen_seen_ms = Time.get_ticks_msec()
	if (Time.get_ticks_msec() - _screen_seen_ms) / 1000.0 >= SCREEN_CLOSE_AFTER_S:
		var closed := ScreenStack.close_all_static()
		run.screens_closed.append([Sim.tick, ",".join(names), closed])
		_screen_seen_ms = -1


# --------------------------------------------------------------------------- deaths

func _handle_death(tick: int) -> void:
	mode = "other"
	stop_moving()
	if run.death_tick < 0:
		run.death_tick = tick
		run.obj_deaths += 1
		if not run.assist and run.obj_deaths > MAX_DEATHS_PER_OBJECTIVE:
			_breach("deaths", "%d deaths on %s" % [run.obj_deaths, run.obj_key])
			return
	var wait := ActionDef.seconds_to_ticks(maxf(DEATH_WAIT_S, 1.0 + 0.25))
	if not run.reload_sent and tick - run.death_tick >= wait:
		run.reload_sent = true
		Events.reload_checkpoint_requested.emit("death")


func _keep_assist(force: bool) -> void:
	if not run.assist or player == null or not player.entity.is_alive():
		return
	var st := player.entity.combatant.statuses
	if force or not st.has(ASSIST_STATUS) or st.remaining_s(ASSIST_STATUS, Sim.tick) < ASSIST_RENEW_S:
		player.entity.apply_status(ASSIST_STATUS, NAN, -1.0, "valley_bot")


## Attribute points: Strength and Endurance alternating (plan §5.1), whenever there are some.
func _allocate_points() -> void:
	var prog = player.progression
	if prog == null or int(prog.unspent_attribute_points) <= 0:
		return
	var key := "strength" if run.allocate_flip % 2 == 0 else "endurance"
	var r: Dictionary = prog.allocate({key: 1})
	if bool(r.get("ok", false)):
		run.allocate_flip += 1
		if int(prog.unspent_attribute_points) == 0:
			run.metrics.note_screen("inventory")


# --------------------------------------------------------------------------- planning

func _plan(tick: int) -> void:
	var fight_target := _fight_target()
	if fight_target != null and _chase_futile(fight_target, tick):
		fight_target = _fight_target()
	if fight_target != null:
		task = {"kind": "fight", "target": fight_target}
		_stall_since = -1
		return
	task = _objective_task(tick)


## True (and the enemy is left alone for CHASE_IGNORE_S) when the bot has fought `t` for
## CHASE_GIVE_UP_S without taking any health off it. Never for the boss.
func _chase_futile(t: EnemyActor, tick: int) -> bool:
	if t.entity == null or t.is_in_group(OgreBoss.GROUP):
		return false
	var id := t.entity.entity_id
	var hp := t.entity.combatant.pools.health
	if id != str(_chase.id) or hp < float(_chase.health) - 0.5:
		_chase = {"id": id, "health": hp, "since": tick}
		return false
	if tick - int(_chase.since) < ActionDef.seconds_to_ticks(CHASE_GIVE_UP_S):
		return false
	_ignored[id] = tick + ActionDef.seconds_to_ticks(CHASE_IGNORE_S)
	_chase = {"id": "", "health": 0.0, "since": -1}
	run.metrics.note(tick, "gave up chasing %s" % id)
	return true


func _is_ignored(e: EnemyActor) -> bool:
	return e.entity != null and int(_ignored.get(e.entity.entity_id, -1)) > Sim.tick


## A hostile to fight now: the nearest aware threat the giant can reach, or an elevated one a
## ranged ability can reach now (none the bot gave up on). null when there is none.
func _fight_target() -> EnemyActor:
	var preferred: Node3D = null
	var t: Dictionary = task
	if str(t.get("kind", "")) in ["kill", "fight"] and t.get("target") is EnemyActor:
		preferred = t.target
	var cands := combat.threats(combat.engage_radius()).filter(func(e: EnemyActor) -> bool: return not _is_ignored(e))
	var best: EnemyActor = null
	for e in cands:
		if combat.is_elevated(e):
			continue
		if not reachable(e.global_position, 3.5):
			continue
		best = e
		break
	if preferred is EnemyActor and combat.is_threat(preferred as EnemyActor) and not _is_ignored(preferred as EnemyActor):
		var p := preferred as EnemyActor
		if best == null or best == p or p.global_position.distance_to(player.global_position) < 8.0 \
				or best.global_position.distance_to(player.global_position) > 5.0:
			if reachable(p.global_position, 3.5) or p.global_position.distance_to(player.global_position) < 6.0:
				return p
	if best != null:
		return best
	for e in cands:
		if combat.is_elevated(e) and (combat.ready_slot(BotCombat.RUNIC_BOLT) != "" or combat.ready_slot(BotCombat.BOULDER_HURL) != ""):
			return e
	return null


## True when a path on the giant's layers from it ends within `tol` m of `pos` (cached 1 s).
func reachable(pos: Vector3, tol := 3.0) -> bool:
	var key := "%d:%d:%d" % [int(pos.x), int(pos.z), player.nav_layers]
	var hit: Variant = _reach_cache.get(key)
	if hit is Array and Sim.tick - int(hit[0]) < 60:
		return bool(hit[1])
	var ok := BotDiagnosis.reaches(level, player.global_position, pos, player.nav_layers, tol)
	_reach_cache[key] = [Sim.tick, ok]
	return ok


func _objective_task(tick: int) -> Dictionary:
	var main := Quests.objective_for(MAIN)
	if main.is_empty():
		return {"kind": "wait", "why": "no main objective"}
	var stage := str(main.stage_id)
	if stage == "leave_hollow" and Quests.quest_state(TUTORIAL) == Quests.ACTIVE \
			and run.tutorial_ticks < ActionDef.seconds_to_ticks(TUTORIAL_BUDGET_S):
		var tut := _tutorial_task()
		if not tut.is_empty():
			return tut
	var errand := _errand_task(stage)
	if not errand.is_empty():
		return errand
	if stage == "village":
		return _village_task(main)
	return _task_for(main, tick)


## The task of an objective's `bot` hint.
func _task_for(o: Dictionary, _tick: int) -> Dictionary:
	var hint: Dictionary = o.get("bot", {})
	var action := str(hint.get("action", "go"))
	var target := str(hint.get("target", ""))
	var pos: Vector3 = o.get("position", Vector3.INF)
	match action:
		"go":
			return {"kind": "go", "pos": _go_goal(o), "radius": 2.0}
		"fight_encounter":
			var fight := _encounter_task(target, pos)
			# The garrison's last members are out of reach (on a terrace, fleeing) and the giant stands
			# at the encounter: it walks on to the stage's other way out (the courtyard's causeway).
			if _stalled(fight) and _first_area(_stage_condition(o)) != "":
				return {"kind": "go", "pos": _go_goal(o), "radius": 2.0, "why": "walk on: the rest is out of reach"}
			return fight
		"kill":
			if str(hint.get("rest_first", "")) != "" and not run.rested_for_boss:
				var rest := _rest_task(str(hint.rest_first), true)
				if not rest.is_empty():
					return rest
			# A hurt giant rests before a kill objective (the forest ogre) at a shrine in reach on
			# its own side of the target (not one it would have to walk past the target to reach).
			var pools := player.entity.combatant.pools
			var where: Vector3 = pos
			var tn := _entity_node(target)
			if tn != null:
				where = tn.global_position
			if pools.health < pools.health_max * KILL_REST_BELOW_HEALTH and where.is_finite():
				var s := _nearest_shrine(KILL_REST_RADIUS_M, where)
				if s != null:
					return {"kind": "rest", "shrine": s, "boss": false}
			var node := _entity_node(target)
			if node is EnemyActor and (node as EnemyActor).entity.is_alive():
				return {"kind": "fight", "target": node}
			var enc := str(hint.get("encounter", ""))
			if enc != "" and director != null and director.encounter_state(enc) == EncounterDirector.ACTIVE:
				return _encounter_task(enc, pos)
			return {"kind": "go", "pos": pos, "radius": 4.0}
		"grow":
			var shrine := _shrine(target)
			if shrine == null:
				return {"kind": "go", "pos": pos, "radius": 3.0}
			return {"kind": "grow", "shrine": shrine, "stage": int(hint.get("stage", player.current_growth_stage() + 1))}
		"hurl_at":
			var prop := _prop(target)
			return {"kind": "hurl", "target": prop} if prop != null else {"kind": "go", "pos": pos, "radius": 3.0}
		"break":
			var enc := str(hint.get("encounter", ""))
			var prop := _prop(target)
			if prop == null:
				return {"kind": "go", "pos": pos, "radius": 3.0}
			return {"kind": "break", "target": prop, "weapon": str(hint.get("weapon", "")), "encounter": enc}
		"interact":
			var node := _prop(target)
			if node == null:
				node = _entity_node(target)
			if node == null:
				return {"kind": "go", "pos": pos, "radius": 3.0}
			var enc := str(hint.get("encounter", ""))
			if enc != "" and director != null and director.encounter_state(enc) == EncounterDirector.ACTIVE \
					and _encounter_alive(enc).size() > 0 and node.global_position.distance_to(player.global_position) < 40.0:
				var guard := _encounter_task(enc, pos)
				if not _stalled(guard):
					return guard
			return {"kind": "interact", "target": node}
		"talk":
			return {"kind": "talk", "npc": target, "dialogue": str(hint.get("dialogue", "")),
				"outcome": str(hint.get("outcome", ""))}
		"wait":
			return {"kind": "wait", "why": "hint wait"}
	return {"kind": "go", "pos": pos, "radius": 3.0}


## True once an encounter task has found nothing to reach for STALL_WALK_ON_S (P17b: the bot stood
## at the courtyard while its last soldiers held a terrace, or at the barrow while the wardens' wolves
## fled, until the stage's watchdog ended the run).
func _stalled(t: Dictionary) -> bool:
	if not bool(t.get("stalled", false)):
		_stall_since = -1
		return false
	if _stall_since < 0:
		_stall_since = Sim.tick
	return Sim.tick - _stall_since >= ActionDef.seconds_to_ticks(STALL_WALK_ON_S)


func _stage_condition(o: Dictionary) -> Variant:
	return Quests.stage_record(Quests.quest_record(str(o.quest_id)), str(o.stage_id)).get("complete_when")


## Where a "go" objective is: the area its condition waits for (entering it completes the stage),
## else its marker.
func _go_goal(o: Dictionary) -> Vector3:
	var cond: Variant = _stage_condition(o)
	var area := _first_area(cond)
	if area != "" and level != null:
		var a := level.area(area)
		if a != null:
			return a.global_position
	var p: Variant = o.get("position", Vector3.INF)
	return p if p is Vector3 else Vector3.INF


static func _first_area(cond: Variant) -> String:
	if typeof(cond) != TYPE_DICTIONARY:
		return ""
	var c: Dictionary = cond
	if str(c.get("type", "")) == "entered":
		return str(c.get("area", ""))
	for sub: Variant in c.get("of", []) if typeof(c.get("of")) == TYPE_ARRAY else []:
		var a := _first_area(sub)
		if a != "":
			return a
	return ""


## Fight an encounter: its nearest living member (the director spawns it near the giant), else go to
## where it is ("stalled" once the giant stands there and every living member is out of reach).
func _encounter_task(encounter_id: String, fallback: Vector3) -> Dictionary:
	var alive := _encounter_alive(encounter_id)
	var best: EnemyActor = null
	var best_d := INF
	for e in alive:
		if combat.is_elevated(e) or e.brain == null or e.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED] \
				or _is_ignored(e):
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < best_d and (d < 8.0 or reachable(e.global_position, 3.5)):
			best = e
			best_d = d
	if best != null:
		return {"kind": "fight", "target": best}
	var center := fallback
	var rec := GameData.get_record(encounter_id)
	if typeof(rec.get("center_m")) == TYPE_ARRAY and level != null:
		var c: Array = rec.center_m
		center = level.global_transform * Vector3(float(c[0]), float(c[1]), float(c[2]))
	if director != null and director.encounter_state(encounter_id) == EncounterDirector.ACTIVE \
			and alive.is_empty() and center.distance_to(player.global_position) < 12.0:
		return {"kind": "wait", "why": "encounter %s: nothing left to reach" % encounter_id}
	# The wait starts within STALL_START_M of the centre and goes on while the giant stays within
	# STALL_KEEP_M (M6 gate: a wolf harassing from behind kept pushing the dodging giant a metre or two
	# past 6 m, the wait restarted every few seconds, and the crown stage ran out its watchdog with the
	# crown in reach).
	var stall_m := STALL_KEEP_M if _stall_since >= 0 else STALL_START_M
	return {"kind": "go", "pos": center, "radius": STALL_START_M,
		"stalled": not alive.is_empty() and center.distance_to(player.global_position) < stall_m}


func _encounter_alive(encounter_id: String) -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	if director == null:
		return out
	for id in director.members_of(encounter_id):
		var n := director.spawned(id) as EnemyActor
		if n != null and n.entity != null and n.entity.is_alive() and not n.is_routed():
			out.append(n)
	return out


# --------------------------------------------------------------------------- the Hollow tutorial

## The optional tutorial (quest.tutorial): two camera toggles, the dummies (light x3, heavy,
## Footfall, a lock), then the sparring post (a block and a dodge through its swing).
func _tutorial_task() -> Dictionary:
	var stage := Quests.stage_of(TUTORIAL)
	match stage:
		"awaken":
			return {"kind": "tutorial_camera"}
		"train":
			var d := level.get_node_or_null("Dummies/valley_hollow_dummy_1") as Node3D
			if d == null:
				return {}
			return {"kind": "tutorial_dummy", "target": d}
		"spar":
			var post := director.spawned("valley.hollow.sparring_post") if director != null else null
			if post == null:
				var m := level.marker("valley.marker.sparring_post")
				return {"kind": "go", "pos": m.global_position if m != null else player.global_position, "radius": 3.0}
			return {"kind": "tutorial_spar", "target": post}
	return {}


# --------------------------------------------------------------------------- errands

## Rests, reforges, the armory's sword and crate, the quarry chest: done on the way when near.
func _errand_task(stage: String) -> Dictionary:
	if combat.threats(combat.engage_radius()).size() > 0:
		return {}
	var t := {}
	var pools := player.entity.combatant.pools
	if pools.health < pools.health_max * REST_BELOW_HEALTH:
		var s := _nearest_shrine(ERRAND_RADIUS_M)
		if s != null:
			t = _errand({"kind": "rest", "shrine": s, "boss": false, "errand": "rest"})
			if not t.is_empty():
				return t
	t = _forge_errand()
	if not t.is_empty():
		t.errand = "reforge"
		t = _errand(t)
		if not t.is_empty():
			return t
	if stage in ["courtyard", "causeway", "boss", "grow3", "tree", "deadfall", "crown"]:
		var rack := _prop("valley.ruins.sword_rack") as WeaponRack
		if rack != null and not rack.taken and player.equipment != null and not player.equipment.owns("weapon.sword") \
				and not player.equipment.owns("weapon.sword_reinforced") and _near(rack, ERRAND_RADIUS_M):
			t = _errand({"kind": "interact", "target": rack, "errand": "sword"})
			if not t.is_empty():
				return t
		var crate := _prop("valley.ruins.armory_crate") as BreakableProp
		if crate != null and not crate.destroyed and _near(crate, ERRAND_RADIUS_M):
			t = _errand({"kind": "break", "target": crate, "weapon": "", "encounter": "", "errand": "armory crate"})
			if not t.is_empty():
				return t
	var chest := _prop("valley.quarry.chest") as BreakableProp
	if chest != null and not chest.destroyed and _near(chest, 25.0):
		return _errand({"kind": "break", "target": chest, "weapon": "", "encounter": "", "errand": "quarry chest"})
	return {}


## `t`, unless the bot has spent ERRAND_GIVE_UP_S on that errand in this level load without getting
## it done: then {} (the errand is skipped from then on, noted once). A rest or reforge that is done
## starts its count again.
func _errand(t: Dictionary) -> Dictionary:
	var key := str(t.get("errand", ""))
	var spent := int(_errand_ticks.get(key, 0))
	if spent >= ActionDef.seconds_to_ticks(ERRAND_GIVE_UP_S):
		if spent < GAVE_UP:
			_errand_ticks[key] = GAVE_UP
			run.metrics.note(Sim.tick, "errand given up after %d s: %s" % [int(ERRAND_GIVE_UP_S), key])
		return {}
	return t


## Two iron and a weapon that can be reforged (the best base weapon owned), at an open forge near.
func _forge_errand() -> Dictionary:
	if player.equipment == null or WorldState.count_of(IRON) < 2:
		return {}
	var base := _upgradable_weapon()
	if base == "":
		return {}
	for id: String in ["valley.village.forge", "valley.ruins.giantforge"]:
		var f := _prop(id) as Forge
		if f != null and f.is_open() and _near(f, ERRAND_RADIUS_M):
			return {"kind": "upgrade", "forge": f, "weapon": base}
	return {}


## The owned weapon to reforge: the sword before the club, one with an upgrade not yet made.
func _upgradable_weapon() -> String:
	for id: String in ["weapon.sword", "weapon.club", "weapon.hammer"]:
		if not player.equipment.owns(id):
			continue
		var up: Variant = GameData.get_record(id).get("upgrade")
		if typeof(up) == TYPE_DICTIONARY and not player.equipment.owns(str((up as Dictionary).get("to", ""))):
			return id
	return ""


func _rest_task(shrine_id: String, boss: bool) -> Dictionary:
	var s := _shrine(shrine_id)
	if s == null:
		return {}
	return {"kind": "rest", "shrine": s, "boss": boss}


## The nearest shrine within `radius` the giant can reach; with `away_from` (a danger), only one
## farther from it than the giant is.
func _nearest_shrine(radius: float, away_from := Vector3.INF) -> Shrine:
	var best: Shrine = null
	var best_d := radius
	for n in get_tree().get_nodes_in_group(Shrine.GROUP):
		var s := n as Shrine
		if s == null or not level.is_ancestor_of(s):
			continue
		if away_from.is_finite() and _flat_dist(s.global_position, away_from) <= _flat_dist(player.global_position, away_from):
			continue
		var d := s.global_position.distance_to(player.global_position)
		if d < best_d and reachable(s.global_position, s.activation_radius_m()):
			best = s
			best_d = d
	return best


# --------------------------------------------------------------------------- the village

## quest.main's `village` stage under the run's policy (plan §5.1 "Village policy sub-plan").
func _village_task(main: Dictionary) -> Dictionary:
	var hint: Dictionary = main.get("bot", {})
	var dialogue := str(hint.get("dialogue", ELDER_DIALOGUE))
	match run.policy:
		"intimidate":
			return {"kind": "talk", "npc": ELDER, "dialogue": dialogue, "outcome": "intimidate"}
		"force":
			var barricade := _prop(BARRICADE)
			if barricade != null and not (barricade as BreakableProp).destroyed:
				return {"kind": "break", "target": barricade, "weapon": "", "encounter": ""}
			return {"kind": "wait", "why": "the barricade is down"}
		"help_cache":
			if str(WorldState.get_flag("quest.village.offer", "")) == "":
				return {"kind": "talk", "npc": ELDER, "dialogue": dialogue, "outcome": "offer_cache"}
			if WorldState.count_of("item.supply_cache") > 0:
				return {"kind": "talk", "npc": ELDER, "dialogue": dialogue, "outcome": "help_cache"}
			var o := Quests.objective_for("quest.village_cache")
			var cache := _prop(CACHE)
			if cache != null and not (cache as ItemPickup).taken:
				var t := {"kind": "interact", "target": cache}
				var alive := _encounter_alive("encounter.quarry_raiders")
				if not alive.is_empty() and cache.global_position.distance_to(player.global_position) < 35.0:
					return _encounter_task("encounter.quarry_raiders", cache.global_position)
				return t
			return {"kind": "go", "pos": o.get("position", Vector3.INF) if not o.is_empty() else player.global_position, "radius": 3.0}
		"help_ogre":
			if str(WorldState.get_flag("quest.village.offer", "")) == "":
				return {"kind": "talk", "npc": ELDER, "dialogue": dialogue, "outcome": "offer_ogre"}
			if WorldState.is_killed(FIELD_OGRE):
				return {"kind": "talk", "npc": ELDER, "dialogue": dialogue, "outcome": "help_ogre"}
			var ogre := _entity_node(FIELD_OGRE)
			if ogre is EnemyActor and (ogre as EnemyActor).entity.is_alive():
				return {"kind": "fight", "target": ogre}
			var o := Quests.objective_for("quest.village_ogre")
			return {"kind": "go", "pos": o.get("position", Vector3.INF) if not o.is_empty() else player.global_position, "radius": 6.0}
	return {"kind": "wait", "why": "unknown policy"}


# --------------------------------------------------------------------------- acting

func _act(tick: int, defending: bool) -> void:
	var kind := str(task.get("kind", "wait"))
	mode = "other"
	if tick < combat.dodge_steer_until():
		return   # a dodge holds its stick for a few ticks
	if tick < _unstick_until:
		mode = "traverse"
		steer_world(_unstick_dir, false)
		return
	if not _retrace.is_empty():
		if tick < _retrace_until and kind != "fight":
			mode = "traverse"
			while not _retrace.is_empty() and _flat_dist(_retrace[0], player.global_position) < WAYPOINT_M:
				_retrace.remove_at(0)
			if not _retrace.is_empty():
				steer_world(_flat(_retrace[0] - player.global_position).normalized(), false)
				return
		# Back where a path leads on (or the retrace ran out): plan again from here.
		_retrace = PackedVector3Array()
		_path = PackedVector3Array()
		_stuck_best = INF
		_stuck_since = tick
	match kind:
		"fight":
			var t: Variant = task.get("target")
			if t is EnemyActor and combat._fightable(t as EnemyActor):
				mode = "combat"
				combat.fight(tick, t as EnemyActor)
				if combat.target != null and combat.target != t:
					task.target = combat.target   # the lock chose another threat close by
			else:
				stop_moving()
		"go":
			_act_go(tick, task.get("pos", Vector3.INF), float(task.get("radius", 2.0)))
		"grow":
			_act_grow(tick)
		"hurl":
			_act_hurl(tick)
		"break":
			_act_break(tick, defending)
		"interact":
			_act_interact(tick)
		"talk":
			_act_talk(tick)
		"rest":
			_act_rest(tick)
		"upgrade":
			_act_upgrade(tick)
		"tutorial_camera":
			_act_tutorial_camera(tick)
		"tutorial_dummy":
			_act_tutorial_dummy(tick)
		"tutorial_spar":
			_act_tutorial_spar(tick, defending)
		_:
			stop_moving()
	if str(task.get("kind", "")).begins_with("tutorial"):
		run.tutorial_ticks += 1
	var errand := str(task.get("errand", ""))
	if errand != "" and int(_errand_ticks.get(errand, 0)) < GAVE_UP:
		_errand_ticks[errand] = int(_errand_ticks.get(errand, 0)) + 1
	_equip_best()


## Walks to `pos` along a path; true once within `radius` (horizontally).
func _act_go(tick: int, pos: Vector3, radius: float) -> bool:
	if not (pos is Vector3) or not pos.is_finite():
		stop_moving()
		return false
	if _flat_dist(player.global_position, pos) <= radius:
		stop_moving()
		_reset_stuck()
		return true
	mode = "traverse"
	steer_path(tick, pos, true)
	_track_stuck(tick, pos)
	return false


func _act_grow(tick: int) -> void:
	var shrine := task.get("shrine") as Shrine
	if shrine == null or not is_instance_valid(shrine):
		return
	var stage := int(task.get("stage", 2))
	if player.current_growth_stage() >= stage:
		return
	var pad := shrine.growth_pad_position()
	if not _act_go(tick, pad, 1.0):
		return
	var check := shrine.can_grow(player, stage)
	if bool(check.get("ok", false)):
		var r := shrine.grow(player, stage)
		run.metrics.note_screen("shrine")
		run.metrics.note(tick, "grow to %d at %s: %s" % [stage, shrine.world_id, r.get("ok", false)])
	elif str(check.get("reason", "")) == "clearance":
		# Something stands in the new capsule: step aside and try again.
		_unstick_dir = Vector3(run.rng.randf_range(-1, 1), 0, run.rng.randf_range(-1, 1)).normalized()
		_unstick_until = tick + 30


func _act_hurl(tick: int) -> void:
	var prop := task.get("target") as BreakableProp
	if prop == null or not is_instance_valid(prop) or prop.destroyed:
		return
	var d := _flat_dist(player.global_position, prop.global_position)
	if d > 20.0 or not _sees(prop.global_position + Vector3.UP):
		_act_go(tick, prop.global_position, 14.0)
		return
	stop_moving()
	var locked := player.targeting.locked_entity()
	var e := prop.get_node_or_null("CombatEntity") as CombatEntity
	if e != null and locked != e:
		if locked != null:
			player.router.inject_edge(&"lock_press")
			return
		if tick % 10 == 0:
			player.camera_rig.yaw = TargetingRules.yaw_of(_flat(prop.global_position - player.global_position))
			player.router.inject_edge(&"lock_press")
		return
	var key := combat.ready_slot(BotCombat.BOULDER_HURL)
	if key != "" and player.controller.state == CombatController.State.LOCOMOTION:
		combat.use_slot(key, "hurl at %s" % prop.world_id)


func _act_break(tick: int, defending: bool) -> void:
	var prop := task.get("target") as BreakableProp
	if prop == null or not is_instance_valid(prop) or prop.destroyed:
		return
	var weapon := str(task.get("weapon", ""))
	if weapon != "" and player.equipment != null and player.equipment.weapon_id() != weapon and player.equipment.owns(weapon):
		player.equipment.equip_weapon(weapon)
	# A blow that does not land (a low crate under the swing, a wall's edge) moves the giant closer:
	# BREAK_STEP_M after every BREAK_SWINGS_PER_STEP blows that took nothing off the prop.
	var e := prop.get_node_or_null("CombatEntity") as CombatEntity
	var health := e.combatant.pools.health if e != null and e.combatant != null else 0.0
	if prop.get_instance_id() != _break_id:
		_break_id = prop.get_instance_id()
		_break_health = health
		_break_swings = 0
		_break_closer = 0.0
	elif health < _break_health - 0.01:
		_break_health = health
		_break_swings = 0
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	var gap := _prop_gap(prop)
	if gap > maxf(0.3, reach * 0.6 - _break_closer):
		_act_go(tick, _approach_point(prop, maxf(0.1, reach * 0.4 - _break_closer)), 0.8)
		return
	stop_moving()
	mode = "combat"
	var c := player.controller
	# P38: a lockable prop the giant may not target (a faction's at peace: P03's hostile-only
	# targeting) refuses the lock; it is struck facing it, as one that cannot be locked.
	if e != null and e.combatant.lockable and player.targeting.may_target(e):
		var locked := player.targeting.locked_entity()
		if locked != e:
			if locked != null:
				player.router.inject_edge(&"lock_press")
				return
			player.camera_rig.yaw = TargetingRules.yaw_of(_flat(prop.global_position - player.global_position))
			if tick % 8 == 0:
				player.router.inject_edge(&"lock_press")
			return
	else:
		if player.targeting.locked_entity() != null:
			player.router.inject_edge(&"lock_press")
		player.camera_rig.yaw = TargetingRules.yaw_of(_flat(prop.global_position - player.global_position))
	if defending or c.state != CombatController.State.LOCOMOTION or tick - _break_swing_tick < 12:
		return
	var edge := &"heavy" if c.preview_reason(&"heavy") == "" else (&"light" if c.preview_reason(&"light") == "" else &"")
	if edge == &"":
		return
	player.router.inject_edge(edge)
	_break_swing_tick = tick
	_break_swings += 1
	if _break_swings >= BREAK_SWINGS_PER_STEP:
		_break_swings = 0
		_break_closer = minf(_break_closer + BREAK_STEP_M, reach)


## Interactables (pickups, racks, the oak) through the real interact edge: walk close, face it,
## press E (at most every 20 ticks).
func _act_interact(tick: int) -> void:
	var node := task.get("target") as Node3D
	if node == null or not is_instance_valid(node):
		return
	if (node is ItemPickup and (node as ItemPickup).taken) or (node is WeaponRack and (node as WeaponRack).taken) \
			or (node is UprootTree and (node as UprootTree).uprooted):
		return
	var radius := float(node.get("radius_m")) if "radius_m" in node else 3.0
	var capsule := float(player.profile.get("capsule_radius_m", 0.85))
	if _flat_dist(player.global_position, node.global_position) > radius + capsule - 0.6:
		_act_go(tick, node.global_position, maxf(1.0, radius + capsule - 1.0))
		return
	stop_moving()
	if player.targeting.locked_entity() != null:
		player.router.inject_edge(&"lock_press")
		return
	var yaw := TargetingRules.yaw_of(_flat(node.global_position - player.global_position))
	player.camera_rig.yaw = yaw
	if absf(TargetingRules.yaw_delta(player.facing_yaw, yaw)) > deg_to_rad(40.0):
		steer_world(_flat(node.global_position - player.global_position).normalized() * 0.2, false)
		return
	if tick - _interact_tick >= 20 and player.controller.state == CombatController.State.LOCOMOTION:
		_interact_tick = tick
		player.router.inject_edge(&"interact")
		if node is UprootTree or node is WeaponRack or node is ItemPickup:
			run.metrics.note(tick, "interact %s" % str(node.get("world_id")))


## The elder (or another talker): walk within 4 m, then the conversation through Quests directly
## (no screen): read the node, choose the policy's outcome, end it.
func _act_talk(tick: int) -> void:
	var npc := _entity_node(str(task.get("npc", "")))
	if npc == null:
		var m := level.marker("valley.marker.elder")
		_act_go(tick, m.global_position if m != null else player.global_position, 3.0)
		return
	var capsule := float(player.profile.get("capsule_radius_m", 0.85))
	if _flat_dist(player.global_position, npc.global_position) > 3.5 + capsule:
		_act_go(tick, npc.global_position, 3.0 + capsule)
		return
	stop_moving()
	if tick - _talked_tick < 90:
		return
	_talked_tick = tick
	var s := Quests.start_dialogue(str(task.get("dialogue", ELDER_DIALOGUE)), str(task.get("npc", "")))
	if s == null:
		run.metrics.note(tick, "talk: %s has nothing to say" % task.get("npc", ""))
		return
	run.metrics.note_screen("dialogue")
	run.metrics.note_dialogue_text(s.text())
	var outcome := str(task.get("outcome", ""))
	var r := {"ok": false}
	if outcome != "" and s.find_choice(outcome) >= 0:
		var before := s.node_id
		r = s.choose_outcome(outcome)
		run.metrics.note_dialogue_text(outcome, false)
		if s.is_active() and s.node_id != before:
			run.metrics.note_dialogue_text(s.text())
	run.metrics.note(tick, "talk %s -> %s (%s)" % [task.get("npc", ""), outcome, r.get("ok", false)])
	if Quests.dialogue != null:
		Quests.end_dialogue()


func _act_rest(tick: int) -> void:
	var s := task.get("shrine") as Shrine
	if s == null or not is_instance_valid(s):
		return
	var spot: Vector3 = (s.get_node("SpawnPoint") as Node3D).global_position if s.has_node("SpawnPoint") else s.global_position
	if not _act_go(tick, spot, 3.0):
		return
	var r := s.rest(player)
	run.metrics.note_screen("shrine")
	if bool(task.get("boss", false)):
		run.rested_for_boss = true
	run.metrics.note(tick, "rest at %s: %s" % [s.world_id, r.get("ok", false)])
	_errand_ticks.erase(str(task.get("errand", "")))
	task = {}
	_next_plan_tick = tick


func _act_upgrade(tick: int) -> void:
	var f := task.get("forge") as Forge
	if f == null or not is_instance_valid(f):
		return
	if not _act_go(tick, f.global_position, 4.5 + float(player.profile.get("capsule_radius_m", 0.85))):
		return
	var base := str(task.get("weapon", ""))
	if player.equipment.weapon_id() != base:
		player.equipment.equip_weapon(base)
		return
	var r := f.upgrade(player)
	run.metrics.note_screen("forge")
	run.metrics.note(tick, "reforge %s at %s: %s" % [base, f.world_id, r.get("ok", false)])
	_errand_ticks.erase(str(task.get("errand", "")))
	task = {}
	_next_plan_tick = tick


## The weapon for the task: the one a prop needs (the Deadfall: the oak), else the best one-handed
## weapon owned (a reforged weapon, else the sword, else the club), else the oak. The oak's swing
## passes over a wolf or a soldier at the giant's feet, so fights use the smaller weapons.
func _equip_best() -> void:
	var eq = player.equipment
	if eq == null or player.controller.state != CombatController.State.LOCOMOTION:
		return
	if str(task.get("kind", "")) == "upgrade":
		return
	var want := ""
	var needed := str(task.get("weapon", ""))
	if needed != "" and eq.owns(needed):
		want = needed
	else:
		for id: String in WEAPON_ORDER:
			if eq.owns(id):
				want = id
				break
	if want == "" and eq.owns(TREE_WEAPON) and player.current_growth_stage() >= 3:
		want = TREE_WEAPON
	if want != "" and eq.weapon_id() != want:
		eq.equip_weapon(want)


# --------------------------------------------------------------------------- the tutorial's acts

func _act_tutorial_camera(tick: int) -> void:
	stop_moving()
	if tick - _tutorial_step_tick >= 12 and _camera_toggles < 2:
		_tutorial_step_tick = tick
		_camera_toggles += 1
		player.router.inject_edge(&"camera_toggle")
	elif _camera_toggles >= 2 and tick - _tutorial_step_tick > 60:
		_camera_toggles = 0   # the lesson did not take: toggle twice again


func _act_tutorial_dummy(tick: int) -> void:
	var d := task.get("target") as Node3D
	if d == null:
		return
	var front := d.global_position + Vector3(2.8 + float(player.profile.get("capsule_radius_m", 0.85)) - 0.85, 0, 0)
	if not _act_go(tick, front, 0.8):
		return
	stop_moving()
	var c := player.controller
	if player.targeting.locked_entity() == null:
		player.camera_rig.yaw = TargetingRules.yaw_of(_flat(d.global_position - player.global_position))
	if c.state != CombatController.State.LOCOMOTION or tick - _tutorial_step_tick < 30:
		return
	_tutorial_step_tick = tick
	var r := player.router
	# The train stage counts the blows that connected with the dummies (hits_on), per kind.
	var ctx := Quests.condition_context()
	var dummies := ["valley.hollow.dummy_1", "valley.hollow.dummy_2"]
	if QuestConditions.hit_count(ctx, dummies, "light", "") < 3:
		r.inject_edge(&"light")
	elif QuestConditions.hit_count(ctx, dummies, "heavy", "") < 1:
		r.inject_edge(&"heavy")
	elif QuestConditions.hit_count(ctx, dummies, "", BotCombat.FOOTFALL) < 1:
		var key := combat.ready_slot(BotCombat.FOOTFALL)
		if key != "":
			combat.use_slot(key, "tutorial footfall")
	elif not WorldState.has_flag("tutorial.lock.done") and player.targeting.locked_entity() == null:
		r.inject_edge(&"lock_press")
	elif player.targeting.locked_entity() != null:
		r.inject_edge(&"lock_press")


## The sparring post: stand in its reach, locked on it (which also teaches the lock); the block lesson
## comes from the bot's defence (its skill's reactions to the post's telegraphed swing); for the
## dodge lesson the bot rolls toward the post through the swing as the telegraph tells it (novice:
## with its timing noise), staying inside the swing so the roll's invulnerability takes the hit.
func _act_tutorial_spar(tick: int, _defending: bool) -> void:
	var post := task.get("target") as Node3D
	if post == null or not is_instance_valid(post):
		return
	var spot := post.global_position + Vector3(0, 0, 3.2)
	if _flat_dist(player.global_position, spot) > 1.5 and not _act_go(tick, spot, 0.8):
		return
	stop_moving()
	var e := post.get_node_or_null("CombatEntity") as CombatEntity
	if player.targeting.locked_entity() != e and tick - _tutorial_step_tick >= 10:
		_tutorial_step_tick = tick
		if player.targeting.locked_entity() != null:
			player.router.inject_edge(&"lock_press")
		else:
			player.camera_rig.yaw = TargetingRules.yaw_of(_flat(post.global_position - player.global_position))
			player.router.inject_edge(&"lock_press")
	if not WorldState.has_flag("tutorial.block.done") or WorldState.has_flag("tutorial.dodge.done"):
		return   # the block lesson comes from the bot's defence
	combat.clear_reactions()   # the dodge lesson wants a roll through the swing, not a block
	var c := (post as EnemyActor).controller if post is EnemyActor else null
	if c == null or c.action == null or c.phase() != ActionDef.Phase.WINDUP:
		return
	if c.instance_id != _spar_instance:
		_spar_instance = c.instance_id
		_spar_lead = 10 + (run.rng.randi_range(-4, 4) if run.skill == BotCombat.NOVICE else 0)
	if c.action.windup_ticks - c.elapsed == _spar_lead and player.controller.state == CombatController.State.LOCOMOTION:
		var toward := _flat(post.global_position - player.global_position).normalized()
		steer_world(toward, false)
		player.router.inject_edge(&"dodge")
		_unstick_dir = toward
		_unstick_until = tick + 3


# --------------------------------------------------------------------------- movement

## Steers along a navigation path to `goal` (re-planned every REPATH_S, when the goal moves or when
## the giant strays OFF_PATH_M from it).
func steer_path(tick: int, goal: Vector3, sprint: bool) -> void:
	if _path.is_empty() or tick >= _repath_tick or _flat_dist(goal, _path_goal) > 2.0 or _off_path():
		_replan(tick, goal)
	while _path_index < _path.size() and _flat_dist(_path[_path_index], player.global_position) < WAYPOINT_M:
		_path_index += 1
	var next := goal if _path_index >= _path.size() else _path[_path_index]
	var to := _flat(next - player.global_position)
	if to.length_squared() < 0.01:
		stop_moving()
		return
	steer_world(to.normalized(), sprint and to.length() > 4.0)


func _replan(tick: int, goal: Vector3) -> void:
	_repath_tick = tick + ActionDef.seconds_to_ticks(REPATH_S)
	_path_goal = goal
	_path = NavQuery.path(level, player.global_position, goal, player.nav_layers, NavQuery.PURPOSE_FAR)
	_path_index = 0
	if _path.size() > 1:
		_path_index = 1


func _off_path() -> bool:
	if _path.size() < 2:
		return false
	var i := clampi(_path_index, 1, _path.size() - 1)
	var a := _path[i - 1]
	var b := _path[i]
	var p := player.global_position
	var seg := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
	return seg.distance_to(Vector3(p.x, 0, p.z)) > OFF_PATH_M


## Steers toward `point`: directly when near (or in sight), along a path otherwise (combat).
func steer_toward(point: Vector3, sprint: bool) -> void:
	var d := _flat_dist(point, player.global_position)
	if d < 8.0:
		steer_world(_flat(point - player.global_position).normalized(), sprint)
		return
	steer_path(Sim.tick, point, sprint)


## Sets the stick so the giant moves along world direction `dir` (movement is camera-relative, or
## target-relative while locked in third person); without a lock the camera turns that way too.
func steer_world(dir: Vector3, sprint: bool) -> void:
	_last_steer_tick = Sim.tick
	var flat := _flat(dir)
	if flat.length_squared() < 1e-6:
		stop_moving()
		return
	var basis_yaw := player.camera_rig.yaw
	var locked := player.targeting.locked_entity()
	if locked != null and locked.is_alive() and not player.camera_rig.is_first_person():
		basis_yaw = player.motor.yaw_to(locked.anchor_position())
	else:
		var want := TargetingRules.yaw_of(flat)
		player.camera_rig.yaw = lerp_angle(player.camera_rig.yaw, want, 0.25)
		basis_yaw = player.camera_rig.yaw
	var local := flat.normalized().rotated(Vector3.UP, -basis_yaw)
	player.router.set_injected_move(Vector2(local.x, -local.z).limit_length(1.0))
	player.router.set_injected_hold(&"sprint", sprint)


func stop_moving() -> void:
	if player == null:
		return
	player.router.set_injected_move(Vector2.ZERO)
	player.router.set_injected_hold(&"sprint", false)


# --------------------------------------------------------------------------- stuck and watchdogs

func _reset_stuck() -> void:
	_stuck_best = INF
	_stuck_since = Sim.tick
	run.stuck_level = 0


## Progress toward a traversal goal: no STUCK_PROGRESS_M closer in STUCK_S is a stuck event, and
## the recovery escalates (sidestep and jump, re-plan, route points, teleport, breach).
func _track_stuck(tick: int, goal: Vector3) -> void:
	if _flat_dist(goal, _stuck_goal) > 3.0:
		_stuck_goal = goal
		_stuck_best = INF
		_stuck_since = tick
	var d := _flat_dist(player.global_position, goal)
	if d < _stuck_best - STUCK_PROGRESS_M:
		_stuck_best = d
		_stuck_since = tick
		run.stuck_level = 0
		return
	if tick - _stuck_since < ActionDef.seconds_to_ticks(STUCK_S):
		return
	_stuck_since = tick
	run.stuck_level += 1
	var how := ""
	match run.stuck_level:
		1:
			how = "sidestep_jump"
			var to := _flat(goal - player.global_position).normalized()
			_unstick_dir = to.cross(Vector3.UP) * (1.0 if run.rng.randf() < 0.5 else -1.0)
			_unstick_until = tick + 60
			player.router.inject_edge(&"jump")
		2:
			# Walked into a pocket the navmesh does not join (chasing an enemy between houses: the
			# giant fits through gaps the bake closed)? Walk back the way it came first.
			var back := _retrace_route(goal)
			if not back.is_empty():
				how = "retrace"
				_retrace = back
				_retrace_until = tick + ActionDef.seconds_to_ticks(RETRACE_S)
			else:
				how = "replan"
			_path = PackedVector3Array()
		3:
			how = "route_points"
			var rp := _route_point_toward(goal)
			if rp.is_finite():
				_replan(tick, rp)
				_repath_tick = tick + ActionDef.seconds_to_ticks(STUCK_S)
		4:
			how = "teleport"
			var to_p := goal
			if _path.size() > 0:
				to_p = _path[mini(_path_index + 1, _path.size() - 1)]
			run.teleports += 1
			GameSession.place_player(player, Transform3D(Basis(Vector3.UP, player.facing_yaw), to_p + Vector3.UP * 0.1))
			_path = PackedVector3Array()
		_:
			how = "none"
	run.metrics.note_stuck(tick, player.global_position, run.obj_key, how)
	if run.stuck_level > 4:
		_breach("stuck", "no progress toward %s after every recovery" % [_v(goal)], goal)


## A breadcrumb every CRUMB_EVERY_TICKS when the giant has moved CRUMB_SPACING_M since the last one.
func _note_crumb(tick: int) -> void:
	if tick % CRUMB_EVERY_TICKS != 0:
		return
	var p := player.global_position
	if _crumbs.is_empty() or _flat_dist(_crumbs[_crumbs.size() - 1], p) >= CRUMB_SPACING_M:
		_crumbs.append(p)
		if _crumbs.size() > CRUMBS_KEPT:
			_crumbs.remove_at(0)


## The way back to the joined navmesh: when no path on the giant's layers leads from where it stands
## to `goal`, the breadcrumbs back to the newest one from which a path does (next first); [] when a
## path leads on from here, or from none of them.
func _retrace_route(goal: Vector3) -> PackedVector3Array:
	var snapped := BotDiagnosis.snap_to_layer(level, goal, player.nav_layers)
	if BotDiagnosis.reaches(level, player.global_position, snapped, player.nav_layers):
		return PackedVector3Array()
	var route := PackedVector3Array()
	for i in range(_crumbs.size() - 1, -1, -1):
		var c := _crumbs[i]
		route.append(c)
		if _flat_dist(c, player.global_position) < CRUMB_SPACING_M:
			continue
		if BotDiagnosis.reaches(level, c, snapped, player.nav_layers):
			return route
	return PackedVector3Array()


## The bot_route_points marker that is nearer the goal than the giant and nearest to the giant.
func _route_point_toward(goal: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	var mine := _flat_dist(player.global_position, goal)
	for n in get_tree().get_nodes_in_group("bot_route_points"):
		var m := n as Node3D
		if m == null or not level.is_ancestor_of(m):
			continue
		if _flat_dist(m.global_position, goal) >= mine:
			continue
		var d := _flat_dist(m.global_position, player.global_position)
		if d < best_d and d > 3.0:
			best = m.global_position
			best_d = d
	return best


func _watchdogs(tick: int) -> void:
	var key := "%s:%s" % [MAIN, Quests.stage_of(MAIN)]
	if key != run.obj_key:
		run.obj_key = key
		run.obj_ticks = 0
		run.obj_deaths = 0
		run.stuck_level = 0
		print("[valley_bot] %.1f s  %s  stage %d  level %d  %s" % [float(tick - run.started_tick) / 60.0, key,
			player.current_growth_stage(), int(player.progression.level) if player.progression != null else 0,
			run.policy])
	run.obj_ticks += 1
	var limit := BOSS_TIMEOUT_S if key.ends_with(":boss") else OBJECTIVE_TIMEOUT_S
	if run.obj_ticks > ActionDef.seconds_to_ticks(limit):
		_breach("timeout", "%s took more than %d s (tick %d)" % [key, int(limit), tick])


## One line of what the bot is doing (--bot-trace=S prints one every S simulated seconds): the task,
## the giant (position, health, controller state, lock) and a fight's target.
func trace_line(tick: int) -> String:
	var pools := player.entity.combatant.pools
	var locked := player.targeting.locked_entity()
	var line := "[valley_bot trace] %.1f s  %s  task %s  giant %s hp %.0f/%.0f %s lock %s" % [
		float(tick - run.started_tick) / 60.0, run.obj_key, str(task.get("kind", "")) + (
			" (%s)" % task.why if task.has("why") else ""), _v(player.global_position), pools.health,
		pools.health_max, CombatController.State.keys()[player.controller.state],
		locked.entity_id if locked != null else "-"]
	var t: Variant = task.get("target")
	if t is Node3D and is_instance_valid(t):
		var n := t as Node3D
		var tid := str(n.get("world_id")) if "world_id" in n else (str(n.get("entity_id")) if "entity_id" in n else str(n.name))
		line += "  target %s at %s (%.1f m)" % [tid, _v(n.global_position),
			_flat_dist(n.global_position, player.global_position)]
		if n is EnemyActor and (n as EnemyActor).entity != null:
			var e := n as EnemyActor
			line += " hp %.0f %s %s%s" % [e.entity.combatant.pools.health,
				CombatController.State.keys()[e.controller.state] if e.controller != null else "?",
				EnemyBrain.AIState.keys()[e.brain.state] if e.brain != null else "?", " guarding" if e.is_guarding() else ""]
	elif task.has("pos"):
		line += "  to %s" % _v(task.pos)
	return line


## A watchdog breach: the diagnosis, then the end of a single run, or (loop) a checkpoint reload.
func _breach(reason: String, detail: String, goal := Vector3.INF) -> void:
	var o := Quests.objective_for(MAIN)
	var radius := 4.0
	var g := goal
	var hint: Dictionary = o.get("bot", {})
	match str(hint.get("action", "")):
		"hurl_at":
			radius = 22.0
		"break", "interact", "kill", "fight_encounter":
			radius = 8.0
		"go":
			g = _go_goal(o) if not g.is_finite() else g
	var diag := BotDiagnosis.diagnose(o, player, level, reason, g, radius, _crumbs)
	diag["detail"] = detail
	diag["task"] = str(task.get("kind", ""))
	diag["policy"] = run.policy
	run.breaches.append(diag)
	run.metrics.note(Sim.tick, "breach %s: %s (%s)" % [reason, detail, diag.classification])
	print("[valley_bot] breach %s: %s -> %s" % [reason, detail, diag.classification])
	if not run.loop:
		_finish("breach")
		return
	run.obj_ticks = 0
	run.obj_deaths = 0
	run.stuck_level = 0
	if GameSession.has_checkpoint():
		Events.reload_checkpoint_requested.emit("debug")


func _check_invariants(tick: int) -> void:
	var fails := BotDiagnosis.check_invariants(get_tree(), player, level, run.metrics, run.dup_seen)
	run.dup_seen = run.metrics.duplicate_rewards.size()
	if tick % 60 == 0 and run.node_growth == "":
		run.node_growth = BotDiagnosis.node_growth_failure(run.metrics.load_samples)
		if run.node_growth != "":
			fails.append(run.node_growth)
	if fails.is_empty():
		return
	for f in fails:
		run.invariant_failures.append({"tick": tick, "failure": f})
		print("[valley_bot] invariant failed: %s" % f)
	_finish("invariant")


# --------------------------------------------------------------------------- the end

func _on_slice_complete(tick: int) -> void:
	stop_moving()
	run.metrics.mark_completed(tick)
	run.metrics.note_screen("end")
	run.completed_runs += 1
	if not run.loop:
		_finish("completed")
		return
	run.loop_runs.append(_run_summary(tick))
	run.metrics.disconnect_events()
	run.run_index += 1
	run.policy = POLICIES[(POLICIES.find(run.options.get("policy", "help_cache")) + run.run_index) % POLICIES.size()]
	var before := run.metrics
	run.metrics = _new_metrics()
	# Node counts span the whole loop: node growth is judged across the new games.
	run.metrics.node_samples = before.node_samples
	run.metrics.load_samples = before.load_samples
	run.metrics.connect_events()
	run.metrics.on_new_game(tick)
	run.obj_key = ""
	run.obj_ticks = 0
	run.obj_deaths = 0
	run.tutorial_ticks = 0
	run.dup_seen = 0
	print("[valley_bot] slice complete; loop run %d: %s" % [run.run_index + 1, run.policy])
	GameSession.change_mode("valley", {"new_game": true})


func _run_summary(tick: int) -> Dictionary:
	var m := run.metrics.result(tick)
	return {"policy": run.policy, "completed": m.completed, "simulated_s": m.simulated_s,
		"human_estimate_s": m.human_estimate_s, "deaths": (m.deaths as Array).size(),
		"village_outcome": m.village_outcome, "duplicates": (m.rewards.duplicates as Array).size(),
		"stuck_events": (m.stuck_events as Array).size()}


func _finish(reason: String) -> void:
	if run.finished:
		return
	run.finished = true
	run.finish_reason = reason
	stop_moving()


## The bot's part of AUTOPILOT_RESULT ("valley_bot"): the options, the metrics, the breaches with
## their diagnoses, the invariant failures and, in a loop, every run's summary.
static func result(tick: int) -> Dictionary:
	if run == null:
		return {}
	var out := run.metrics.result(tick)
	out["bot"] = {"policy": run.policy, "start_policy": str(run.options.get("policy", "")), "skill": run.skill,
		"assist": run.assist, "loop": run.loop, "seed": run.seed_value}
	out["finish_reason"] = run.finish_reason if run.finish_reason != "" else "timeout"
	out["breaches"] = run.breaches.duplicate(true)
	out["diagnosis"] = run.breaches[run.breaches.size() - 1] if not run.breaches.is_empty() else {}
	out["world_blocked"] = run.breaches.filter(func(b: Dictionary) -> bool:
		return str(b.get("classification", "")) == BotDiagnosis.WORLD_BLOCKED).size()
	out["invariant_failures"] = run.invariant_failures.duplicate(true)
	out["node_growth"] = run.node_growth
	out["screens_closed"] = run.screens_closed.duplicate(true)
	out["level_loads"] = run.level_loads
	out["teleports"] = run.teleports
	out["notes"] = run.metrics.notes.duplicate(true)
	if run.loop:
		var runs := run.loop_runs.duplicate(true)
		out["loop_runs"] = runs
		out["loop_completed"] = run.completed_runs
	return out


# --------------------------------------------------------------------------- lookups

func _entity_node(id: String) -> Node3D:
	var e := Sim.get_entity(id)
	if e != null and e.actor != null and is_instance_valid(e.actor) and (e.actor as Node).is_inside_tree():
		return e.actor as Node3D
	return null


func _prop(world_id: String) -> Node3D:
	if level == null or world_id == "":
		return null
	return level.get_node_or_null("Props/" + world_id.validate_node_name()) as Node3D


func _shrine(world_id: String) -> Shrine:
	if level == null:
		return null
	var s := level.get_node_or_null("Shrines/" + world_id.validate_node_name()) as Shrine
	if s != null:
		return s
	for n in get_tree().get_nodes_in_group(Shrine.GROUP):
		if n is Shrine and ((n as Shrine).world_id == world_id or (n as Shrine).shrine_id == world_id):
			return n
	return null


func _near(n: Node3D, radius: float) -> bool:
	return n != null and _flat_dist(n.global_position, player.global_position) <= radius


## How far the giant's capsule is from the prop's collision: a ray from the giant toward the prop's
## centre, a metre up, to the prop's own surface (the centre itself when the ray meets none of the
## prop's shapes within 25 m), minus the capsule radius.
func _prop_gap(prop: Node3D) -> float:
	var capsule := float(player.profile.get("capsule_radius_m", 0.85))
	var from := player.global_position + Vector3.UP * 1.0
	var to := prop.global_position + Vector3.UP * 1.0
	var flat := _flat_dist(from, to)
	if flat > 25.0:
		return flat - capsule
	var exclude: Array[RID] = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(to.x, from.y, to.z),
			HitQueryAdapter.LAYER_BREAKABLE | HitQueryAdapter.LAYER_WORLD, exclude)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col := hit.collider as Node
		if col != null and (col == prop or prop.is_ancestor_of(col)):
			flat = minf(flat, _flat_dist(from, hit.position))
			break
		exclude.append(hit.rid)   # something else in the way: look past it
	return flat - capsule


## A point in front of the prop on the giant's side, `dist` m plus the capsule from its surface
## (as _prop_gap measures it), on the giant's layer.
func _approach_point(prop: Node3D, dist: float) -> Vector3:
	var away := _flat(player.global_position - prop.global_position)
	if away.length_squared() < 1e-3:
		away = Vector3.BACK
	var capsule := float(player.profile.get("capsule_radius_m", 0.85))
	var surface := _flat_dist(player.global_position, prop.global_position) - (_prop_gap(prop) + capsule)
	var p := prop.global_position + away.normalized() * (maxf(0.0, surface) + capsule + dist)
	return BotDiagnosis.snap_to_layer(level, p, player.nav_layers)


func _sees(point: Vector3) -> bool:
	var from := player.targeting.eye()
	return HitQueryAdapter.line_clear(player.get_world_3d().direct_space_state, from, point,
		HitQueryAdapter.LAYER_WORLD, [])


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	if not a.is_finite() or not b.is_finite():
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
