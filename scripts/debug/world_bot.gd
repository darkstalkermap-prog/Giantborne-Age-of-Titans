class_name WorldBot
extends ValleyBot
## The world bot (P38; plan M6-M9 §3.22, §6.1, decision 28): the Valley bot grown into the campaign. It
## plays quest.world_main from world_start (--mode=world --new-game) or, with --bot-campaign, from the
## Valley's New Game through the Kings' Door (the Valley's own logic until slice.completed, then this
## bot's) to the Stone Throne, under an oath policy in any order; it explores, uses the map's fast
## travel, measures how the world plays (RunMetrics with §5.15's world segments, WorldMetrics) and
## checks the stability invariants (the Valley's and the world's, BotDiagnosis) every tick.
##
## It is a ValleyBot: the same run in a static (it survives the reloads of deaths, checkpoints and fast
## travel), the same skill profiles and assisted mode (BotCombat, status.bot_assist), the same
## movement, interaction, shrine and forge acts, the same stuck recovery and breach handling, and it
## runs PROCESS_MODE_ALWAYS and calls the screen-backed APIs directly: dialogue through Quests with
## the choice of the policy's outcome found node by node (_say), the yield prompt through
## EnemyActor.p34_decide (never by tapping its buttons: the prompt arms only after 0.75 s with every
## input let go and decides only on a 0.8 s hold - M8 gate F7), shrine growth and rest, the ancestry
## and talent choices by policy (PlayerProgression), forge refits (Forge.upgrade) and fast travel
## (GameSession.travel_to "fast_travel", as the map's Travel does).
##
## Policies (--bot-oaths=march:help,wood:drive,crown:parley is also the order; two oaths by default,
## three with --bot-oath-count=3), or a preset (--bot-preset=):
##   peaceful  march help, wood drive, crown parley; Harrok by talk when it is offered, else spared;
##             Corvane spared; the ancestry Stoneblood (a parley token)
##   conqueror march force, wood slay, crown breach; Corvane struck, Harrok slain; Wildheart
##   mixed     march intimidate, crown sabotage, wood slay; Harrok spared; Stormborn
## --bot-champion=spare|slay|talk and --bot-corvane=spare|strike override the preset's.
##
## Each plan tick (every 6 ticks): a yield waiting for its decision is decided (the screens' hook,
## before any pausing screen is closed); a fight when aware hostiles are near (BotCombat: formations
## through their lock group, the banner first; engines broken by blows or Crag Hurl; the Matriarch with
## the den's braziers); then errands (rest when hurt and a shrine is within 150 m, reinforce and
## titanforge at an open forge near, the ancestry and the talents at a shrine); then the main thread's
## stage: the beacon, grow4, the oaths in the policy's order (each resolution its own sub-plan of
## talks, breaches, fights, burns and heaves; growth to stage 5 after the first), grow6 at the Standing
## Stones (up the Ironway below stage 6), the Moot, the champion, the throne.
##
## Routing: BotRoute (the road graph by stage, then NavQuery legs of at most 250 m on the titan map
## with the stage's query mask, direct edges walked straight, waits for chunks that are not ready,
## fast travel to a visited waystone or shrine near a far goal - refused mid-fight: "Not in the middle
## of a fight.", then it walks).
##
## Watchdogs: 300 s per main-thread stage (600 s for a boss stage: the den, the Iron Regiment, the
## champion; 900 s for the oaths' other stages), plus a travel allowance of the stage's road route at
## TRAVEL_ALLOWANCE_MPS; 5 deaths per stage (unassisted); stuck. The diagnosis adds the index route and
## per-chunk path checks (BotDiagnosis.diagnose_world).

const WGROUP := "world_bot"
const WORLD_MAIN := "quest.world_main"
const WORLD_LEVEL := "level.world"
const VALLEY_LEVEL := "level.valley"
const OATHS := ["march", "wood", "crown"]
const OATH_QUESTS := {"march": "quest.oath_march", "wood": "quest.oath_wood", "crown": "quest.oath_crown"}
const RESOLUTIONS := {"march": ["help", "intimidate", "force"], "wood": ["slay", "drive"],
	"crown": ["breach", "sabotage", "parley"]}
const PRESETS := {
	"peaceful": {"oaths": "march:help,wood:drive,crown:parley", "champion": "talk", "corvane": "spare",
		"ancestry": "ancestry.stoneblood"},
	"conqueror": {"oaths": "march:force,wood:slay,crown:breach", "champion": "slay", "corvane": "strike",
		"ancestry": "ancestry.wildheart"},
	"mixed": {"oaths": "march:intimidate,crown:sabotage,wood:slay", "champion": "spare", "corvane": "spare",
		"ancestry": "ancestry.stormborn"},
}
const PRESET_ORDER := ["peaceful", "conqueror", "mixed"]
const CHAMPIONS := ["spare", "slay", "talk"]
const ANCESTRIES := ["ancestry.stoneblood", "ancestry.stormborn", "ancestry.wildheart"]
## Talents in the order each skill learns them (plan §6.1: a fixed build per skill; passives only, so the
## loadout the Valley taught stays).
const TALENT_BUILDS := {
	"novice": ["talent.guardian_stone_hide", "talent.guardian_steady_stance", "talent.destroyer_heavy_hands",
		"talent.guardian_tireless", "talent.destroyer_iron_grip", "talent.destroyer_bone_breaker",
		"talent.guardian_grounded", "talent.destroyer_juggernaut", "talent.guardian_protector",
		"talent.destroyer_bloodied_fury", "talent.primordial_kindled", "talent.primordial_runic_mind"],
	"expert": ["talent.destroyer_heavy_hands", "talent.destroyer_iron_grip", "talent.destroyer_bone_breaker",
		"talent.guardian_stone_hide", "talent.guardian_steady_stance", "talent.destroyer_juggernaut",
		"talent.guardian_tireless", "talent.destroyer_bloodied_fury", "talent.guardian_grounded",
		"talent.guardian_protector", "talent.primordial_kindled", "talent.primordial_runic_mind"],
}
## The weapons in the order the bot fights with them (owned, and fitting the stage when one does).
const WORLD_WEAPON_ORDER := ["weapon.club_titan", "weapon.sword_titan", "weapon.hammer_titan", "weapon.axe_titan",
	"weapon.club_reinforced", "weapon.sword_reinforced", "weapon.hammer_reinforced", "weapon.axe",
	"weapon.sword", "weapon.club", "weapon.hammer"]
const ITEM_IRON := "item.iron_ingot"
const ITEM_TITAN := "item.titan_iron"
const ITEM_BANNER := "item.brannock_banner"

const STAGE_TIMEOUT_S := 300.0
const BOSS_STAGE_TIMEOUT_S := 600.0
const OATHS_TIMEOUT_S := 900.0
## The watchdog's travel allowance: the stage's road route length at this speed (a stage-4 walk is
## about 7 m/s; half of it leaves room for the fights on the way).
const TRAVEL_ALLOWANCE_MPS := 4.0
const WORLD_REST_RADIUS_M := 150.0
const WORLD_REST_BELOW := 0.45
const FORGE_RADIUS_M := 150.0
const SHRINE_CHOICE_RADIUS_M := 60.0
const FAST_TRAVEL_RETRY_S := 30.0
## The Matriarch: a brazier is broken while she stands this close to it (her brazier_radius_m is 8).
const BRAZIER_BURN_M := 7.5
## The drive-out: until the den's flags hold (nests burned, wall open) she is struck only while her
## health is above this share - killed before they hold, she would be slain, not driven out.
const DRIVE_HOLD_FRAC := 0.35
## --bot-explore: each oath's region, and how long one POI is tried before it is given up.
const OATH_REGIONS := {"march": "region.crownmarch", "wood": "region.greywood", "crown": "region.aldmere"}
const EXPLORE_GIVE_UP_S := 120.0
## The objective kinds that fight on their own terms at their place (the den: the drive-out's order;
## the battle: crews and fort ballistae first; the duel): within FIGHT_OWNER_RADIUS_M of the place's
## marker the plan keeps the objective although threats are near.
const FIGHT_OWNERS := {"matriarch": "world.marker.troll_den", "battle": "world.marker.fort_bailey",
	"duel": "world.marker.moot_ring"}
const FIGHT_OWNER_RADIUS_M := 120.0
## An engaged arena's leash: the giant turns back once it stands this share of the disengage margin
## outside the arena's floor, and walks until within the second share (a dodge's drift does not flip
## it on and off at one line).
const ARENA_LEASH_SHARE := 0.4
const ARENA_LEASH_BACK_SHARE := 0.25
## Ranged blows at an enemy or engine above reach: given up after this long without hurting it, then
## ignored for this long.
const RANGED_GIVE_UP_S := 8.0
const RANGED_IGNORE_S := 120.0
## A boss fight's respawn point: the waystone within this of its place is taken first; the bot waits at
## it this long for the checkpoint (taken out of combat).
const RESPAWN_POINT_RADIUS_M := 160.0
const RESPAWN_POINT_WAIT_S := 15.0
## How near the giant must come to a talker (beyond its reach): the talker's radius + the capsule, less.
const TALK_SLACK_M := 1.0
const TALK_RETRY_TICKS := 90
const WORLD_KINDS := ["travel", "say", "smash", "exit", "heave_at", "battle", "matriarch", "duel", "throne",
	"choose_ancestry"]


## The world part of the run (ValleyBot.Run.world): the policy, the oath plan and what the world bot
## must remember across reloads.
class WorldRun extends RefCounted:
	var oaths: Array = []              ## [[oath, resolution], ...] in the order they are taken
	var oath_count := 2
	var champion := "spare"
	var corvane := "spare"
	var preset := ""
	var ancestry := ""
	var explore := 0.0
	var campaign := false
	var loop_presets: Array = []
	var metrics: WorldMetrics = null
	var fast_travel_block: Dictionary = {}   ## checkpoint id -> the tick it may be tried again
	var stage_route_m := 0.0
	var stage_limit_s := STAGE_TIMEOUT_S
	var invariant_state: Dictionary = {}
	var talents_tried: Dictionary = {}
	var decided: Array = []            ## [tick, boss id, outcome]
	var refused: Dictionary = {}       ## what -> the last refusal line (noted once)
	var explored: Dictionary = {}      ## poi id -> true once visited (or given up)
	var world_started_tick := -1
	var valley_done_tick := -1
	## --bot-until=<flag>: the run ends ("until") once this world flag holds (the gate's smoke run stops
	## at Brannock's oath: oath.march.done).
	var until_flag := ""
	## Boss fights' respawn points (_respawn_point_first): waystone id -> true once given up, and
	## "at:<id>" -> the tick the giant reached it.
	var respawn_given_up: Dictionary = {}
	## The encounter budget in the world (see _on_member_spawned): spawns that broke it, and the
	## largest count of counted combatants seen (it may pass the cap when a faction turns hostile).
	var budget_failures: PackedStringArray = []
	var max_counted := 0
	var over_cap_ticks := 0


var route: BotRoute = null
var wrun: WorldRun:
	get:
		return run.world as WorldRun if run != null else null

var _node_cache: Dictionary = {}       ## world id -> WeakRef of its node (loaded chunks)
var _budget_director: EncounterDirector = null
var _budget_seen := 0                  ## counted combatants at the last look (tick, spawn or flag)
var _spawn_positions: Dictionary = {}  ## entity id -> its spawn position (encounter records)
var _talk_tick := -1000
var _leashed := false
var _ranged_tries: Dictionary = {}     ## entity id -> [first tick, health then, last tick] (_ranged_futile)
var _world: WorldRoot = null


# --------------------------------------------------------------------------- configuration

## Starts a world run (once per process): the Valley bot's options (skill, assist, seed, loop, trace,
## and for a campaign --bot-village) and the world's (see parse_world_options).
static func configure_world(args: PackedStringArray) -> Run:
	if run != null:
		return run
	var r := ValleyBot.configure(ValleyBot.parse_options(args))
	var w := WorldRun.new()
	apply_world_options(w, parse_world_options(args))
	r.world = w
	w.metrics = WorldMetrics.new(r.metrics)
	w.metrics.connect_events()
	_use_world_segments(r, w)
	return r


static func _use_world_segments(r: Run, w: WorldRun) -> void:
	var defs: Array = []
	if w.campaign:
		defs.append_array(RunMetrics.SEGMENTS)
	defs.append_array(RunMetrics.WORLD_SEGMENTS)
	r.metrics.use_segments(defs, WorldBot.world_segment)


## Forgets the run (tests).
static func reset_world() -> void:
	if run != null and run.world != null and (run.world as WorldRun).metrics != null:
		(run.world as WorldRun).metrics.disconnect_events()
	ValleyBot.reset()


## The world options of the user args: {"oaths": [[oath, resolution], ...], "oath_count", "champion",
## "corvane", "preset", "ancestry", "explore", "campaign"}. --bot-preset= sets the oaths, the champion,
## Corvane's fate and the ancestry; --bot-oaths=, --bot-champion=, --bot-corvane=, --bot-ancestry=,
## --bot-oath-count=, --bot-explore= and --bot-campaign override it. Unknown values warn and keep the
## default (the peaceful preset).
static func parse_world_options(args: PackedStringArray) -> Dictionary:
	var out := {"preset": "peaceful"}
	var explicit := {}
	for arg in args:
		if arg.begins_with("--bot-preset="):
			var p := arg.substr(13).strip_edges().to_lower()
			if PRESETS.has(p):
				out.preset = p
			else:
				push_warning("WorldBot: unknown --bot-preset=%s (peaceful | conqueror | mixed)" % p)
		elif arg.begins_with("--bot-oaths="):
			var list := parse_oaths(arg.substr(12))
			if list.is_empty():
				push_warning("WorldBot: --bot-oaths=%s names no oath (march:help,wood:drive,crown:parley)" % arg.substr(12))
			else:
				explicit["oaths"] = list
		elif arg.begins_with("--bot-champion="):
			var c := arg.substr(15).strip_edges().to_lower()
			if c in CHAMPIONS:
				explicit["champion"] = c
			else:
				push_warning("WorldBot: unknown --bot-champion=%s (spare | slay | talk)" % c)
		elif arg.begins_with("--bot-corvane="):
			var v := arg.substr(14).strip_edges().to_lower()
			if v in ["spare", "strike"]:
				explicit["corvane"] = v
		elif arg.begins_with("--bot-ancestry="):
			var a := arg.substr(15).strip_edges().to_lower()
			if not a.begins_with("ancestry."):
				a = "ancestry." + a
			if a in ANCESTRIES:
				explicit["ancestry"] = a
		elif arg.begins_with("--bot-oath-count="):
			explicit["oath_count"] = clampi(int(arg.substr(17)), 1, 3)
		elif arg.begins_with("--bot-explore="):
			explicit["explore"] = clampf(float(arg.substr(14)), 0.0, 1.0)
		elif arg == "--bot-campaign":
			explicit["campaign"] = true
		elif arg.begins_with("--bot-until="):
			explicit["until"] = arg.substr(12).strip_edges()
	var preset: Dictionary = PRESETS[out.preset]
	out["oaths"] = parse_oaths(str(preset.oaths))
	out["champion"] = str(preset.champion)
	out["corvane"] = str(preset.corvane)
	out["ancestry"] = str(preset.ancestry)
	out["oath_count"] = 2
	out["explore"] = 0.0
	out["campaign"] = false
	out.merge(explicit, true)
	return out


## "march:help,wood:drive" -> [["march", "help"], ["wood", "drive"]] (unknown oaths or resolutions
## are left out with a warning; an oath named twice counts once).
static func parse_oaths(text: String) -> Array:
	var out: Array = []
	var seen := {}
	for part in text.split(",", false):
		var kv := part.strip_edges().to_lower().split(":")
		var oath := kv[0].strip_edges()
		if not RESOLUTIONS.has(oath) or seen.has(oath):
			push_warning("WorldBot: unknown or repeated oath '%s'" % part)
			continue
		var res := kv[1].strip_edges() if kv.size() > 1 else str((RESOLUTIONS[oath] as Array)[0])
		if not (res in RESOLUTIONS[oath]):
			push_warning("WorldBot: unknown resolution '%s' for the %s oath" % [res, oath])
			continue
		seen[oath] = true
		out.append([oath, res])
	return out


static func apply_world_options(w: WorldRun, o: Dictionary) -> void:
	w.preset = str(o.get("preset", ""))
	w.oaths = (o.get("oaths", []) as Array).duplicate(true)
	w.oath_count = clampi(int(o.get("oath_count", 2)), 1, 3)
	w.champion = str(o.get("champion", "spare"))
	w.corvane = str(o.get("corvane", "spare"))
	w.ancestry = str(o.get("ancestry", ""))
	w.explore = float(o.get("explore", 0.0))
	w.campaign = bool(o.get("campaign", false))
	w.until_flag = str(o.get("until", ""))
	# every oath the order leaves out follows (a third oath, or one the second needs)
	for oath: String in OATHS:
		var named := false
		for pair: Array in w.oaths:
			if pair[0] == oath:
				named = true
		if not named:
			w.oaths.append([oath, str((RESOLUTIONS[oath] as Array)[0])])


## The segment of this tick (RunMetrics' resolver): the Valley's by quest.main's stage until the
## prologue is done (a campaign), then the world's by quest.world_main's stage and the oaths won
## (RunMetrics.WORLD_SEGMENTS).
static func world_segment() -> String:
	if not Quests.is_complete(Quests.MAIN_QUEST_ID) and Quests.quest_state(Quests.MAIN_QUEST_ID) == Quests.ACTIVE:
		return RunMetrics.segment_of_stage(Quests.stage_of(Quests.MAIN_QUEST_ID))
	if Quests.is_complete(WORLD_MAIN):
		return ""
	match Quests.stage_of(WORLD_MAIN):
		"kings_door", "beacon", "grow4":
			return "w1_opening"
		"oaths":
			return "w2_first_oath" if oaths_done() == 0 else "w3_second_oath"
		"grow6":
			var p := Engine.get_main_loop().root.get_tree().get_first_node_in_group("player") as GiantPlayer \
				if Engine.get_main_loop() is SceneTree else null
			var idx := WorldIndex.for_level(WORLD_LEVEL)
			if p != null and idx != null and GameSession.current_level_id() == WORLD_LEVEL \
					and idx.region_at(p.global_position) == "region.stonehold":
				return "w5_stonehold"
			return "w4_roaming"
		"moot", "champion", "throne":
			return "w5_stonehold"
	return ""


static func oaths_done() -> int:
	var n := 0
	for oath: String in OATHS:
		if QuestConditions.truthy(WorldState.get_flag("oath.%s.done" % oath)):
			n += 1
	return n


static func oath_done(oath: String) -> bool:
	return QuestConditions.truthy(WorldState.get_flag("oath.%s.done" % oath))


# --------------------------------------------------------------------------- binding

func _ready() -> void:
	super()
	add_to_group(WGROUP)


func _on_level_loaded() -> void:
	super()
	_world = level as WorldRoot
	_node_cache.clear()
	route = BotRoute.new(level.index() if level != null else null, level)
	if wrun != null:
		wrun.metrics.note_level_loaded(level)
		if _world != null and wrun.world_started_tick < 0:
			wrun.world_started_tick = Sim.tick
	_stuck_goal = Vector3.INF
	_watch_budget(level.director() if level != null else null)


# --------------------------------------------------------------------------- the encounter budget

## The director's rule (P10a, P17b): new members wait while max_active_enemies counted combatants
## live, but a member already in the world when its faction turns hostile stays in the fight and
## counts from then on - so the count may pass the cap (the conqueror's march: Brannock's garrison
## turns at the south gate beside the shield wall, 16 > 12). The Valley bot's invariant (count <=
## cap at every tick) does not hold in the world; the world bot checks the rule itself: no counted
## member spawns while the count is already at the cap. The count is re-read at every bot tick,
## every flag change (a faction turning) and every spawn.
func _watch_budget(d: EncounterDirector) -> void:
	if _budget_director != null and is_instance_valid(_budget_director) \
			and _budget_director.member_spawned.is_connected(_on_member_spawned):
		_budget_director.member_spawned.disconnect(_on_member_spawned)
	_budget_director = d
	_budget_seen = d.active_combatant_count() if d != null else 0
	if d != null:
		d.member_spawned.connect(_on_member_spawned)
	if not Events.flag_changed.is_connected(_on_budget_flag):
		Events.flag_changed.connect(_on_budget_flag)


func _budget_alive() -> bool:
	return _budget_director != null and is_instance_valid(_budget_director) and _budget_director.is_inside_tree()


func _on_member_spawned(_encounter_id: String, entity_id: String, _node: Node3D) -> void:
	if not _budget_alive() or wrun == null:
		return
	var d := _budget_director
	var n := d.active_combatant_count()
	if n > d.max_active_enemies and n > _budget_seen:
		wrun.budget_failures.append("%s spawned with %d counted combatants (cap %d)" % [
			entity_id, n, d.max_active_enemies])
	_budget_seen = n


func _on_budget_flag(_tick: int, _id: String, _value: Variant) -> void:
	if _budget_alive():
		_budget_seen = _budget_director.active_combatant_count()


## The per-tick part: the largest count and the ticks over the cap (metrics), then a fresh baseline.
func _budget_tick() -> void:
	if not _budget_alive() or wrun == null:
		return
	var d := _budget_director
	_budget_seen = d.active_combatant_count()
	wrun.max_counted = maxi(wrun.max_counted, _budget_seen)
	if _budget_seen > d.max_active_enemies:
		wrun.over_cap_ticks += 1


func _in_world() -> bool:
	return _world != null and is_instance_valid(_world)


## The navigation layers the giant's paths use here: the titan query mask in the world.
func _nav_mask() -> int:
	return BotDiagnosis.layers_for(player, level)


func reachable(pos: Vector3, tol := 3.0) -> bool:
	if not _in_world():
		return super(pos, tol)
	var mask := _nav_mask()
	var key := "%d:%d:%d" % [int(pos.x), int(pos.z), mask]
	var hit: Variant = _reach_cache.get(key)
	if hit is Array and Sim.tick - int(hit[0]) < 60:
		return bool(hit[1])
	var ok := BotDiagnosis.reaches(level, player.global_position, pos, mask, tol)
	_reach_cache[key] = [Sim.tick, ok]
	return ok


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
	if wrun != null:
		wrun.metrics.on_tick(tick, player, _world)
	_check_invariants(tick)
	if run.finished:
		return
	if player.controller.state == CombatController.State.DEAD:
		_handle_death(tick)
		return
	run.death_tick = -1
	_keep_assist(false)
	_allocate_points()
	if _campaign_done():
		_on_campaign_complete(tick)
		return
	if wrun.until_flag != "" and QuestConditions.truthy(WorldState.get_flag(wrun.until_flag)):
		stop_moving()
		run.metrics.note(tick, "--bot-until: %s holds" % wrun.until_flag)
		_finish("until")
		return
	if _valley_part() and _slice_done() and wrun.valley_done_tick < 0:
		wrun.valley_done_tick = tick
		run.metrics.note(tick, "the prologue is done: the world bot takes over")
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


## True while a campaign run is still in the Valley's prologue (the Valley bot's own logic plays it).
func _valley_part() -> bool:
	return wrun != null and wrun.campaign and not _in_world() \
		and not QuestConditions.truthy(WorldState.get_flag("slice.completed", false))


func _campaign_done() -> bool:
	return Quests.is_complete(WORLD_MAIN) or QuestConditions.truthy(WorldState.get_flag("campaign.completed", false))


func _on_campaign_complete(tick: int) -> void:
	stop_moving()
	run.metrics.mark_completed(tick)
	run.metrics.note_screen("end")
	run.completed_runs += 1
	if not run.loop:
		_finish("completed")
		return
	run.loop_runs.append(_world_summary(tick))
	run.run_index += 1
	var preset: String = PRESET_ORDER[(PRESET_ORDER.find(wrun.preset) + 1) % PRESET_ORDER.size()]
	var o := parse_world_options(PackedStringArray(["--bot-preset=" + preset]))
	o.campaign = wrun.campaign
	apply_world_options(wrun, o)
	var before := run.metrics
	run.metrics.disconnect_events()
	wrun.metrics.disconnect_events()
	run.metrics = _new_metrics()
	run.metrics.node_samples = before.node_samples
	run.metrics.load_samples = before.load_samples
	run.metrics.connect_events()
	run.metrics.on_new_game(tick)
	wrun.metrics = WorldMetrics.new(run.metrics)
	wrun.metrics.connect_events()
	_use_world_segments(run, wrun)
	wrun.world_started_tick = -1
	wrun.decided.clear()
	wrun.fast_travel_block.clear()
	wrun.talents_tried.clear()
	wrun.explored.clear()
	wrun.respawn_given_up.clear()
	run.obj_key = ""
	run.obj_ticks = 0
	run.obj_deaths = 0
	run.dup_seen = 0
	print("[world_bot] the campaign is complete; loop run %d: %s" % [run.run_index + 1, preset])
	GameSession.change_mode("world", {"new_game": true})


func _world_summary(tick: int) -> Dictionary:
	var m := run.metrics.result(tick)
	return {"preset": wrun.preset, "oaths": wrun.oaths.slice(0, wrun.oath_count), "completed": m.completed,
		"simulated_s": m.simulated_s, "human_estimate_s": m.human_estimate_s, "deaths": (m.deaths as Array).size(),
		"outcomes": _outcomes(), "duplicates": (m.rewards.duplicates as Array).size(),
		"stuck_events": (m.stuck_events as Array).size()}


# --------------------------------------------------------------------------- screens and yields

## The yield prompt is answered first (a yielded boss decided by policy through p34_decide), then the
## Valley bot's rule closes whatever pausing screen is open.
func _handle_screens() -> void:
	_decide_yields()
	super()


func _decide_yields() -> void:
	if wrun == null or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyActor
		if e == null or not is_instance_valid(e) or e.entity == null or not bool(e.get("yielded")):
			continue
		if str(e.get("yield_decided")) != "":
			continue
		var boss := e.yield_boss_id()
		var outcome := "spare"
		if boss == "battle.iron_regiment" or e.entity.entity_id == "world.aldmere.corvane":
			outcome = "strike" if wrun.corvane == "strike" else "spare"
		elif e.entity.entity_id == "world.stonehold.harrok":
			outcome = "strike" if wrun.champion == "slay" else "spare"
		if e.p34_decide(outcome):
			wrun.decided.append([Sim.tick, boss, outcome])
			run.metrics.note(Sim.tick, "yield of %s decided: %s" % [boss, outcome])
			run.metrics.note_screen("yield")
			if Quests.dialogue != null:
				Quests.end_dialogue()


# --------------------------------------------------------------------------- points, talents, ancestry

func _allocate_points() -> void:
	super()
	if wrun == null or player.progression == null or player.entity.combatant.pools.in_combat():
		return
	if Sim.tick % 30 != 0 or not _near_shrine(SHRINE_CHOICE_RADIUS_M):
		return
	var prog = player.progression
	if prog.has_method("ancestry_offered") and bool(prog.ancestry_offered()) and wrun.ancestry != "":
		var r: Dictionary = prog.choose_ancestry(wrun.ancestry)
		if bool(r.get("ok", false)):
			run.metrics.note_screen("ancestry")
			run.metrics.note(Sim.tick, "ancestry chosen: %s" % wrun.ancestry)
	if int(prog.get("talent_points")) > 0:
		for id: String in TALENT_BUILDS.get(run.skill, TALENT_BUILDS.novice):
			if prog.knows_talent(id) or wrun.talents_tried.has(id + ":" + str(prog.level)):
				continue
			var r: Dictionary = prog.learn_talent(id)
			if bool(r.get("ok", false)):
				run.metrics.note_screen("talents")
				run.metrics.note(Sim.tick, "talent learned: %s" % id)
				break
			wrun.talents_tried[id + ":" + str(prog.level)] = true


func _near_shrine(radius: float) -> bool:
	for n in get_tree().get_nodes_in_group(Shrine.GROUP):
		var s := n as Shrine
		if s != null and s.is_inside_tree() and _flat_dist(s.global_position, player.global_position) <= radius:
			return true
	return false


# --------------------------------------------------------------------------- planning

func _plan(tick: int) -> void:
	if _valley_part():
		super(tick)
		return
	var objective := _respawn_point_first(_objective_task(tick), tick)
	var owner := str(FIGHT_OWNERS.get(str(objective.get("kind", "")), ""))
	if owner != "" and _flat_dist(player.global_position, _where(owner)) <= FIGHT_OWNER_RADIUS_M:
		task = objective
		_stall_since = -1
		return
	var fight_target := _fight_target()
	if fight_target != null and _chase_futile(fight_target, tick):
		fight_target = _fight_target()
	if fight_target != null and not _fight_ignored_now(fight_target):
		task = {"kind": "fight", "target": fight_target}
		_stall_since = -1
		return
	task = objective


## Before a boss fight (the den, the battle - from the fort gate's breach on - and the duel) the waystone
## nearest its place (within RESPAWN_POINT_RADIUS_M) is made the respawn point, as a player would: a
## death in the fight then wakes beside it. The first crown run died in the battle and woke at the
## Kingsgate shelf, a kilometre and 200 s of walking away, with the battle to start again. The
## waystone is walked into (its 10 m radius); it is taken out of combat, so the bot waits there up to
## RESPAWN_POINT_WAIT_S, then goes on either way. Never once the fight is engaged: no checkpoint
## commits then, and the walk out of the arena pulled against its leash (the Moot's duel engages as
## the champion's stage begins, with the Moot foot waystone 58 m outside the ring).
func _respawn_point_first(objective: Dictionary, tick: int) -> Dictionary:
	if not _in_world() or route == null or route.index == null:
		return objective
	if not GameSession.engaged_fights().is_empty():
		return objective
	var kind := str(objective.get("kind", ""))
	var place := Vector3.INF
	if FIGHT_OWNERS.has(kind):
		place = _where(str(FIGHT_OWNERS[kind]))
	elif kind == "smash" and str(objective.get("id", "")) == "world.aldmere.fort_gate":
		place = _where("world.marker.fort_bailey")
	if not place.is_finite():
		return objective
	var best := ""
	var best_d := RESPAWN_POINT_RADIUS_M
	for id in route.index.checkpoint_ids():
		var c := route.index.checkpoint(id)
		var p: Variant = c.get("position")
		if str(c.get("kind", "")) != "waystone" or typeof(p) != TYPE_VECTOR3:
			continue
		var open := true
		for f: Variant in c.get("requires_flags", PackedStringArray()):
			if not QuestConditions.truthy(WorldState.get_flag(str(f))):
				open = false
		var d := _flat_dist(p, place)
		if open and d < best_d:
			best = id
			best_d = d
	if best == "" or GameSession.respawn_id == best or wrun.respawn_given_up.has(best):
		return objective
	var at: Vector3 = route.index.checkpoint(best).position
	if _flat_dist(at, player.global_position) <= 8.0:
		var since := int(wrun.respawn_given_up.get("at:" + best, -1))
		if since < 0:
			wrun.respawn_given_up["at:" + best] = tick
		elif tick - since > ActionDef.seconds_to_ticks(RESPAWN_POINT_WAIT_S):
			wrun.respawn_given_up[best] = true
			run.metrics.note(tick, "the waystone %s was not taken (fighting near it): on without it" % best)
			return objective
		return {"kind": "wait", "why": "at %s for the respawn point" % best}
	return _travel_task(at, 4.0, "respawn point " + best)


## A fight the current task overrides: none (every aware hostile near is fought), except a yielded or
## stood-down boss and a neutral or fleeing actor (BotCombat.is_threat already leaves those out).
func _fight_ignored_now(_t: EnemyActor) -> bool:
	return false


## The Valley's choice, but in the world an enemy out of melee reach above the giant is fought only
## while a ranged blow is ready, and given up (RANGED_IGNORE_S) when those blows have not hurt it in
## RANGED_GIVE_UP_S: the Valley's choice kept such an enemy as the task's preferred target, BotCombat
## stands still under a target it cannot reach, and the giant stood under Fort Aldmere's wall - its
## archers 16 m up, no lock taken, no bolt thrown, the target switching between four of them so the
## Valley's chase give-up never ran out - instead of breaking the gate beside it, until the watchdog.
## The toll fort's tower archers (part of an encounter to clear) are still shot down by bolts. Else
## the nearest threat on the giant's own ground, else none (the objective goes on).
func _fight_target() -> EnemyActor:
	var t := super()
	if t == null or not _in_world() or not combat.is_elevated(t):
		return t
	if _ranged_ready() and not _ranged_futile(t.entity.entity_id, t.entity.combatant.pools.health, Sim.tick):
		return t
	for e in combat.threats(combat.engage_radius()):
		if not _is_ignored(e) and not combat.is_elevated(e) and reachable(e.global_position, 3.5):
			return e
	return null


func _ranged_ready() -> bool:
	return combat.ready_slot(BotCombat.RUNIC_BOLT) != "" or combat.ready_slot(BotCombat.BOULDER_HURL) != ""


## True when ranged blows at `id` (its health now `hp`) have been tried for RANGED_GIVE_UP_S without
## hurting it (a lock refused, a bolt that never left): it is then ignored for RANGED_IGNORE_S. A pause
## of over a second between tries, or any damage, starts the count again.
func _ranged_futile(id: String, hp: float, tick: int) -> bool:
	var rec: Array = _ranged_tries.get(id, [])
	if rec.is_empty() or tick - int(rec[2]) > 60 or hp < float(rec[1]) - 0.5:
		_ranged_tries[id] = [tick, hp, tick]
		return false
	rec[2] = tick
	if tick - int(rec[0]) < ActionDef.seconds_to_ticks(RANGED_GIVE_UP_S):
		return false
	_ignored[id] = tick + ActionDef.seconds_to_ticks(RANGED_IGNORE_S)
	_ranged_tries.erase(id)
	run.metrics.note(tick, "gave up ranged blows at %s" % id)
	return true


func _objective_task(tick: int) -> Dictionary:
	if _valley_part():
		return super(tick)
	var errand := _world_errand()
	if not errand.is_empty():
		return errand
	var o := Quests.objective_for(WORLD_MAIN)
	if o.is_empty():
		return {"kind": "wait", "why": "no world objective"}
	match str(o.stage_id):
		"kings_door":
			return _exit_task("valley.exit.kings_door")
		"beacon":
			return _beacon_task()
		"grow4":
			return _grow_task("world.shrine.kingsgate", 4)
		"oaths":
			return _oaths_task()
		"grow6":
			var third := _third_oath_task()
			if not third.is_empty():
				return third
			if player.current_growth_stage() < 5:
				return _grow5_task(_where("world.shrine.stones"))
			return _grow_task("world.shrine.stones", 6)
		"moot":
			return _travel_task(_where("world.area.moot"), 25.0, "the Moot")
		"champion":
			return _champion_task()
		"throne":
			return _interact_task("world.stonehold.stone_throne")
	return {"kind": "wait", "why": "stage %s" % o.stage_id}


# --------------------------------------------------------------------------- errands

## Rest when hurt and a shrine is near, reinforce or titanforge at an open forge near (nothing when
## threats are near). The ancestry and the talents are taken at shrines (_allocate_points).
func _world_errand() -> Dictionary:
	if combat.threats(combat.engage_radius()).size() > 0:
		return {}
	var pools := player.entity.combatant.pools
	if pools.health < pools.health_max * WORLD_REST_BELOW:
		var s := _nearest_world_shrine(WORLD_REST_RADIUS_M)
		if s != null:
			var t := _errand({"kind": "rest", "shrine": s, "boss": false, "errand": "rest"})
			if not t.is_empty():
				return t
	var forge := _forge_errand_world()
	if not forge.is_empty():
		forge.errand = "reforge"
		return _errand(forge)
	return {}


func _nearest_world_shrine(radius: float) -> Shrine:
	var best: Shrine = null
	var best_d := radius
	for n in get_tree().get_nodes_in_group(Shrine.GROUP):
		var s := n as Shrine
		if s == null or not s.is_inside_tree():
			continue
		var d := _flat_dist(s.global_position, player.global_position)
		if d < best_d:
			best = s
			best_d = d
	return best


## The equipped weapon (or the best owned) has a refit this forge does and its cost is held: an open
## forge within FORGE_RADIUS_M.
func _forge_errand_world() -> Dictionary:
	if player.equipment == null:
		return {}
	var weapon := _refit_candidate()
	if weapon == "":
		return {}
	var up: Dictionary = GameData.get_record(weapon).get("upgrade", {})
	var tier := str(up.get("forge_tier", "iron"))
	for n in get_tree().get_nodes_in_group("forges"):
		var f := n as Forge
		if f == null or not f.is_inside_tree() or not f.is_open() or not f.does_tier(tier):
			continue
		if _flat_dist(f.global_position, player.global_position) <= FORGE_RADIUS_M:
			return {"kind": "upgrade", "forge": f, "weapon": weapon}
	return {}


## The owned weapon to refit next: the best of WORLD_WEAPON_ORDER with an upgrade whose cost is held.
func _refit_candidate() -> String:
	for id: String in WORLD_WEAPON_ORDER:
		if not player.equipment.owns(id):
			continue
		var up: Variant = GameData.get_record(id).get("upgrade")
		if typeof(up) != TYPE_DICTIONARY or player.equipment.owns(str((up as Dictionary).get("to", ""))):
			continue
		var ok := true
		for c: Variant in (up as Dictionary).get("cost", []):
			if typeof(c) == TYPE_DICTIONARY and WorldState.count_of(str(c.get("item", ""))) < int(c.get("count", 1)):
				ok = false
		return id if ok else ""
	return ""


func _equip_best() -> void:
	if not _in_world() and not (wrun != null and wrun.valley_done_tick >= 0):
		super()
		return
	var eq = player.equipment
	if eq == null or player.controller.state != CombatController.State.LOCOMOTION:
		return
	if str(task.get("kind", "")) == "upgrade":
		return
	var stage := player.current_growth_stage()
	var want := ""
	var fallback := ""
	for id: String in WORLD_WEAPON_ORDER:
		if not eq.owns(id):
			continue
		if fallback == "":
			fallback = id
		if not PlayerEquipment.too_small_at(GameData.get_record(id), stage):
			want = id
			break
	if want == "":
		want = fallback
	if want != "" and eq.weapon_id() != want:
		eq.equip_weapon(want)


# --------------------------------------------------------------------------- the main thread's tasks

func _beacon_task() -> Dictionary:
	var enc := "encounter.crownmarch_kingsgate_scouts"
	if not _encounter_cleared(enc):
		var fight := _world_encounter_task(enc)
		if not fight.is_empty() and not _stalled(fight):
			return fight
	return _interact_task("world.crownmarch.kingsgate_beacon_fire")


func _grow_task(shrine_id: String, stage: int) -> Dictionary:
	if player.current_growth_stage() >= stage:
		return {"kind": "wait", "why": "grown"}
	var s := _shrine(shrine_id)
	if s == null or not s.is_inside_tree():
		return _travel_task(_where(shrine_id), 20.0, shrine_id)
	return {"kind": "grow", "shrine": s, "stage": stage}


## Growth to stage 5 (one oath won): at the stage-5 shrine nearest `toward` (the next goal).
func _grow5_task(toward: Vector3) -> Dictionary:
	var best := ""
	var best_d := INF
	for id: String in ["world.shrine.greywood", "world.shrine.aldmere", "world.shrine.steps"]:
		var p := _where(id)
		if not p.is_finite():
			continue
		var d := _flat_dist(p, player.global_position) + (_flat_dist(p, toward) if toward.is_finite() else 0.0)
		if d < best_d:
			best = id
			best_d = d
	return _grow_task(best, 5) if best != "" else {"kind": "wait", "why": "no stage-5 shrine"}


## True when growing to stage 5 is open now (an oath won, level 9).
func _can_grow5() -> bool:
	return player.current_growth_stage() == 4 and oaths_done() >= 1 and player.progression != null \
		and int(player.progression.level) >= 9


func _oaths_task() -> Dictionary:
	var done := 0
	for pair: Array in wrun.oaths:
		if done >= wrun.oath_count:
			break
		var oath := str(pair[0])
		if oath_done(oath):
			done += 1
			continue
		if _can_grow5():
			return _grow5_task(_oath_anchor(oath))
		var explore := _explore_task(oath)
		if not explore.is_empty():
			return explore
		return _oath_task(oath, str(pair[1]))
	return {"kind": "wait", "why": "the oaths are won"}


## --bot-explore=<share> (plan §6.1 "Exploration"): before an oath, the giant visits that share of its
## region's POIs not yet discovered when the oath is first taken up (those its stage may reach),
## nearest first, each until discovered or given up after EXPLORE_GIVE_UP_S; {} when none is due.
## POIs found on the way count.
func _explore_task(oath: String) -> Dictionary:
	if wrun.explore <= 0.0 or route == null or route.index == null:
		return {}
	var key := "oath:" + oath
	if not wrun.explored.has(key):
		var todo := _undiscovered_pois(str(OATH_REGIONS.get(oath, "")))
		wrun.explored[key] = {"set": todo, "quota": ceili(wrun.explore * todo.size())}
		run.metrics.note(Sim.tick, "explore before the %s oath: %d of %d POIs" % [oath, int(wrun.explored[key].quota), todo.size()])
	var plan: Dictionary = wrun.explored[key]
	var done := 0
	var best := ""
	var best_d := INF
	for id: String in plan.set:
		if _poi_found(id) or wrun.explored.has(id):
			done += 1
			continue
		var d := _flat_dist(route.index.pois[id].position, player.global_position)
		if d < best_d:
			best = id
			best_d = d
	if done >= int(plan.quota) or best == "":
		return {}
	var started := int(wrun.explored.get("since:" + best, -1))
	if started < 0:
		wrun.explored["since:" + best] = Sim.tick
	elif Sim.tick - started > ActionDef.seconds_to_ticks(EXPLORE_GIVE_UP_S):
		wrun.explored[best] = "given up"
		run.metrics.note(Sim.tick, "explore: %s given up" % best)
		return _explore_task(oath)
	var poi: Dictionary = route.index.pois[best]
	return _travel_task(poi.position, maxf(4.0, float(poi.get("radius", 20.0)) * 0.5), "explore " + best)


static func _poi_found(id: String) -> bool:
	var v: Variant = WorldState.get_flag(Discovery.discovered_flag(id))
	return QuestConditions.truthy(v) and str(v) != Discovery.REVEALED


## The ids of `region`'s POIs not yet discovered that the giant's stage may reach (sorted).
func _undiscovered_pois(region: String) -> PackedStringArray:
	var out := PackedStringArray()
	if region == "" or route == null or route.index == null:
		return out
	for id: String in route.index.pois:
		var poi: Dictionary = route.index.pois[id]
		if str(poi.get("region", "")) != region or int(poi.get("min_stage", 0)) > player.current_growth_stage():
			continue
		if not _poi_found(id):
			out.append(id)
	out.sort()
	return out


## With --bot-oath-count=3 the third oath is won before grow6.
func _third_oath_task() -> Dictionary:
	if wrun.oath_count < 3:
		return {}
	for pair: Array in wrun.oaths:
		if not oath_done(str(pair[0])):
			if _can_grow5():
				return _grow5_task(_oath_anchor(str(pair[0])))
			return _oath_task(str(pair[0]), str(pair[1]))
	return {}


## Where an oath begins (its talker's place).
func _oath_anchor(oath: String) -> Vector3:
	match oath:
		"march":
			return _where("world.marker.brannock_green")
		"wood":
			return _where("world.marker.hollowmere_green")
		"crown":
			return _where("world.marker.war_camp_edge")
	return Vector3.INF


func _oath_task(oath: String, resolution: String) -> Dictionary:
	match oath:
		"march":
			return _march_task(resolution)
		"wood":
			return _wood_task(resolution)
		"crown":
			return _crown_task(resolution)
	return {"kind": "wait", "why": "unknown oath %s" % oath}


# ---- Brannock's oath

func _march_task(res: String) -> Dictionary:
	var edda := "world.crownmarch.edda"
	match res:
		"intimidate":
			return _say_task(edda, "dialogue.edda", "intimidate", _where("world.marker.brannock_green"))
		"force":
			if not WorldState.is_destroyed("world.crownmarch.brannock_south_gate") \
					and not QuestConditions.truthy(WorldState.get_flag("world.brannock.gate_broken")):
				return _smash_task("world.crownmarch.brannock_south_gate")
			return _say_task(edda, "dialogue.edda", "force", _where("world.crownmarch.edda_hall"))
		_:
			if not QuestConditions.truthy(WorldState.get_flag("oath.march.met")):
				return _say_task(edda, "dialogue.edda", "offer_help", _where("world.marker.brannock_green"))
			var steps: Array = []
			if not WorldState.is_destroyed("world.crownmarch.toll_gate"):
				steps.append(["gate", _where("world.crownmarch.toll_gate")])
			if not _encounter_cleared("encounter.crownmarch_toll_fort"):
				steps.append(["fort", _where("encounter.crownmarch_toll_fort")])
			if not _encounter_cleared("encounter.crownmarch_raiders"):
				steps.append(["raiders", _where("encounter.crownmarch_raiders")])
			if steps.is_empty():
				return _say_task(edda, "dialogue.edda", "help", _where("world.crownmarch.edda_hall"))
			steps.sort_custom(func(a: Array, b: Array) -> bool:
				return _flat_dist(a[1], player.global_position) < _flat_dist(b[1], player.global_position))
			match str(steps[0][0]):
				"gate":
					return _smash_task("world.crownmarch.toll_gate")
				"fort":
					return _world_encounter_task("encounter.crownmarch_toll_fort")
				_:
					return _world_encounter_task("encounter.crownmarch_raiders")


# ---- the Greywood's oath

func _wood_task(res: String) -> Dictionary:
	var sedge := "world.greywood.sedge"
	var outcome := str(WorldState.get_flag("boss.matriarch.outcome", ""))
	if outcome != "":
		return _say_task(sedge, "dialogue.sedge", "slay" if outcome == "slain" else "drive",
			_where("world.marker.hollowmere_green"))
	if not QuestConditions.truthy(WorldState.get_flag("oath.wood.met")):
		var bargain := res == "drive" and player.progression != null and str(player.progression.get("ancestry")) == "ancestry.stormborn"
		return _say_task(sedge, "dialogue.sedge", "bargain" if bargain else "accept", _where("world.marker.hollowmere_green"))
	return {"kind": "matriarch", "resolution": res}


# ---- the crown's oath

func _crown_task(res: String) -> Dictionary:
	match res:
		"breach":
			if not WorldState.is_destroyed("world.aldmere.fort_gate"):
				return _smash_task("world.aldmere.fort_gate")
			return {"kind": "battle"}
		"sabotage":
			var best := ""
			var best_d := INF
			for id: String in ["world.aldmere.camp_catapult_1", "world.aldmere.camp_ballista_1", "world.aldmere.camp_ballista_2",
					"world.aldmere.camp_catapult_2", "world.aldmere.ridge_ballista_1", "world.aldmere.ridge_ballista_2",
					"world.aldmere.ridge_ballista_3"]:
				if WorldState.is_destroyed(id):
					continue
				var d := _flat_dist(_where(id), player.global_position)
				if d < best_d:
					best = id
					best_d = d
			if best != "":
				return _smash_task(best)
			return {"kind": "wait", "why": "the engines are wrecked: the army withdraws"}
		_:
			if not QuestConditions.truthy(WorldState.get_flag("oath.crown.parley_accepted")):
				var token := _parley_token()
				if token == "":
					# the deserters' word: spare Sergeant Wynn at the burned mill
					return _say_task("world.aldmere.deserter_wynn", "dialogue.deserters", "spare",
						_where("world.marker.deserters_mill"))
				return _say_task("world.aldmere.herald", "dialogue.herald", "parley_" + token, _where("world.marker.war_camp_edge"))
			return _say_task("world.aldmere.fort_parley", "dialogue.corvane", "parley", _where("world.marker.fort_gate"))


## The parley token the giant holds now (the herald's order): Brannock's banner, the deserters' word,
## Stoneblood blood, stature; "" when none.
func _parley_token() -> String:
	if WorldState.count_of(ITEM_BANNER) > 0:
		return "banner"
	if QuestConditions.truthy(WorldState.get_flag("oath.crown.token_deserters")):
		return "deserters"
	if player.progression != null and str(player.progression.get("ancestry")) == "ancestry.stoneblood":
		return "stoneblood"
	if player.current_growth_stage() >= 5:
		return "stature"
	return ""


# ---- the champion

func _champion_task() -> Dictionary:
	if str(WorldState.get_flag("boss.harrok.outcome", "")) != "":
		return {"kind": "wait", "why": "the champion is settled"}
	if wrun.champion == "talk" and _talk_ending_open():
		return _say_task("world.stonehold.moot_challenge", "dialogue.harrok", "yielded_talk", _where("world.marker.moot_gate"))
	return {"kind": "duel"}


func _talk_ending_open() -> bool:
	return player.current_growth_stage() >= 6 and oaths_done() >= 3 \
		and QuestConditions.truthy(WorldState.get_flag("world.skarn.support"))


# --------------------------------------------------------------------------- task builders

func _travel_task(pos: Vector3, radius: float, why := "") -> Dictionary:
	return {"kind": "travel", "pos": pos, "radius": radius, "why": why}


## A conversation: walk to the talker (its NPC, or a talker post), then the outcome (node by node).
func _say_task(npc_id: String, dialogue_id: String, outcome: String, fallback: Vector3) -> Dictionary:
	return {"kind": "say", "npc": npc_id, "dialogue": dialogue_id, "outcome": outcome, "pos": fallback}


func _smash_task(world_id: String) -> Dictionary:
	return {"kind": "smash", "id": world_id}


func _interact_task(world_id: String) -> Dictionary:
	var n := _world_node(world_id)
	if n == null:
		return _travel_task(_where(world_id), 12.0, world_id)
	return {"kind": "interact", "target": n}


func _exit_task(exit_id: String) -> Dictionary:
	if _in_world():
		return {"kind": "wait", "why": "already in the world"}
	return {"kind": "exit", "id": exit_id}


## An encounter of the world: its nearest living member (as the Valley's), else its centre.
func _world_encounter_task(encounter_id: String) -> Dictionary:
	if director == null:
		return _travel_task(_where(encounter_id), 10.0, encounter_id)
	return _encounter_task(encounter_id, _where(encounter_id))


func _encounter_cleared(encounter_id: String) -> bool:
	if QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(encounter_id))):
		return true
	return director != null and director.encounter_state(encounter_id) == EncounterDirector.CLEARED


# --------------------------------------------------------------------------- acting

func _act(tick: int, defending: bool) -> void:
	var kind := str(task.get("kind", "wait"))
	if _in_world() and _arena_leash(tick):
		return
	if not (kind in WORLD_KINDS) and not (_in_world() and kind == "go"):
		super(tick, defending)
		return
	mode = "other"
	if tick < combat.dodge_steer_until():
		return
	if tick < _unstick_until:
		mode = "traverse"
		steer_world(_unstick_dir, false)
		return
	if not _retrace.is_empty():
		if tick < _retrace_until:
			mode = "traverse"
			while not _retrace.is_empty() and _flat_dist(_retrace[0], player.global_position) < WAYPOINT_M:
				_retrace.remove_at(0)
			if not _retrace.is_empty():
				steer_world(_flat(_retrace[0] - player.global_position).normalized(), false)
				return
		_retrace = PackedVector3Array()
		if route != null:
			route.reset_leg()
		_stuck_best = INF
		_stuck_since = tick
	match kind:
		"travel", "go":
			_act_travel(tick, task.get("pos", Vector3.INF), float(task.get("radius", 4.0)))
		"say":
			_act_say(tick)
		"smash":
			_act_smash(tick, defending)
		"exit":
			_act_exit(tick)
		"battle":
			_act_battle(tick, defending)
		"matriarch":
			_act_matriarch(tick, defending)
		"duel":
			_act_duel(tick)
		_:
			stop_moving()
	_equip_best()


## A boss arena's disengage rule (P34) resets the attempt - the boss at full health - when the giant
## stays beyond the floor by the arena's margin (20 m) for 5 s. A fight drifts (a chase, a knock-back,
## Harrok's charges, the dodges away from his blows): while an arena is engaged and the giant stands
## more than ARENA_LEASH_SHARE of that margin outside its floor, it walks back toward the floor's centre
## (the boss follows) until within ARENA_LEASH_BACK_SHARE, instead of fighting on. Each walk back is
## its own for the stuck watch: one that ends got back in, so the next does not inherit its time (the
## Moot's duel drifts out through the gate again and again, each walk back to the same line). True
## while it walks.
func _arena_leash(tick: int) -> bool:
	if tick < combat.dodge_steer_until():
		return false
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		var a := n as BossArena
		if a == null or not a.is_inside_tree() or a.state != BossArena.State.ENGAGED:
			continue
		var out := a.outside_m(player.global_position)
		if out <= a.disengage_margin_m * (ARENA_LEASH_BACK_SHARE if _leashed else ARENA_LEASH_SHARE):
			continue
		mode = "traverse"
		if not _leashed:
			_leashed = true
			_reset_stuck()
			run.metrics.note(tick, "back into %s's arena (%.0f m outside)" % [a.boss_id, out])
		_act_go(tick, a.global_position, 4.0)
		return true
	_leashed = false
	return false


## Walks (or fast-travels) to `pos`: true once within `radius`.
func _act_travel(tick: int, pos: Vector3, radius: float) -> bool:
	if not (pos is Vector3) or not pos.is_finite():
		stop_moving()
		return false
	if _flat_dist(player.global_position, pos) <= radius:
		stop_moving()
		_reset_stuck()
		return true
	if _in_world() and _try_fast_travel(tick, pos):
		return false
	return _act_go(tick, pos, radius)


## Fast travel toward a far goal (BotRoute.fast_travel_point): through the map's way, as a player would
## (a map screen, then Travel). A refusal (enemies close, a fight engaged: "Not in the middle of a
## fight.") is noted and the giant walks; the same checkpoint is not tried again for
## FAST_TRAVEL_RETRY_S.
func _try_fast_travel(tick: int, pos: Vector3) -> bool:
	if route == null or route.index == null:
		return false
	var cp := BotRoute.fast_travel_point(route.index, player.global_position, pos, player.current_growth_stage(),
		func(id: String) -> bool: return QuestConditions.truthy(WorldState.get_flag("visited." + id)),
		func(f: String) -> bool: return QuestConditions.truthy(WorldState.get_flag(f)))
	if cp == "" or tick < int(wrun.fast_travel_block.get(cp, -1)):
		return false
	var lv := GameSession.current_level_id()
	var why := GameSession.travel_refusal(lv, cp, "fast_travel")
	if why != "":
		wrun.fast_travel_block[cp] = tick + ActionDef.seconds_to_ticks(FAST_TRAVEL_RETRY_S)
		wrun.metrics.note_fast_travel(tick, GameSession.respawn_id, cp, false, why)
		run.metrics.note(tick, "fast travel to %s refused: %s" % [cp, why])
		return false
	stop_moving()
	wrun.metrics.note_fast_travel(tick, GameSession.respawn_id, cp, true, "")
	run.metrics.note(tick, "fast travel to %s" % cp)
	var r := GameSession.travel_to(lv, cp, "fast_travel")
	if not bool(r.get("ok", false)):
		wrun.fast_travel_block[cp] = tick + ActionDef.seconds_to_ticks(FAST_TRAVEL_RETRY_S)
		return false
	return true


## The world's movement: BotRoute (road graph, legs on the titan map) instead of one path; the Valley's
## steering elsewhere.
func steer_path(tick: int, goal: Vector3, sprint: bool) -> void:
	if not _in_world() or route == null:
		super(tick, goal, sprint)
		return
	route.stage = player.current_growth_stage()
	route.layers = _nav_mask()
	if route.goal_changed(goal):
		route.plan(player.global_position, goal)
	var p := route.steer(player.global_position, tick, _world)
	var to := _flat(p - player.global_position)
	if to.length_squared() < 0.01:
		stop_moving()
		return
	steer_world(to.normalized(), sprint and to.length() > 4.0)


## Stuck in the world: progress is measured along the route (its remaining length), so a winding road
## is not mistaken for no progress; the recovery is the Valley's (sidestep and jump, a new route or the
## breadcrumbs back, a recorded teleport to the leg's next point), then a breach.
func _track_stuck(tick: int, goal: Vector3) -> void:
	if not _in_world() or route == null:
		super(tick, goal)
		return
	if _flat_dist(goal, _stuck_goal) > 3.0:
		_stuck_goal = goal
		_stuck_best = INF
		_stuck_since = tick
	var d := route.remaining_m(player.global_position) if not route.goal_changed(goal) else _flat_dist(player.global_position, goal)
	if d < _stuck_best - STUCK_PROGRESS_M:
		_stuck_best = d
		_stuck_since = tick
		run.stuck_level = 0
		return
	if route.waiting_chunk != "":
		_stuck_since = tick   # the leg waits for a chunk to load: not stuck
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
			var back := _retrace_route(goal)
			if not back.is_empty():
				how = "retrace"
				_retrace = back
				_retrace_until = tick + ActionDef.seconds_to_ticks(RETRACE_S)
			else:
				how = "replan"
			route.plan(player.global_position, goal)
		3:
			how = "replan_far"
			route.plan(player.global_position, goal)
			route.reset_leg()
			_unstick_dir = -_flat(goal - player.global_position).normalized()
			_unstick_until = tick + 45
		4:
			how = "teleport"
			var to_p := goal
			if route.leg.size() > route.leg_index + 1:
				to_p = route.leg[route.leg_index + 1]
			elif route.step < route.points.size():
				to_p = route.points[route.step]
			var ground := _world.height_at(to_p) if _world != null else NAN
			if not is_nan(ground):
				to_p.y = ground
			run.teleports += 1
			GameSession.place_player(player, Transform3D(Basis(Vector3.UP, player.facing_yaw), to_p + Vector3.UP * 0.3))
			route.reset_leg()
		_:
			how = "none"
	run.metrics.note_stuck(tick, player.global_position, run.obj_key, how)
	if run.stuck_level > 4:
		_breach("stuck", "no progress toward %s after every recovery" % [_v(goal)], goal)


func _retrace_route(goal: Vector3) -> PackedVector3Array:
	if not _in_world():
		return super(goal)
	var mask := _nav_mask()
	var snapped := BotDiagnosis.snap_to_layer(level, goal, mask)
	if _flat_dist(goal, player.global_position) > BotRoute.LEG_MAX_M:
		return PackedVector3Array()   # a far goal: the route replans instead
	if BotDiagnosis.reaches(level, player.global_position, snapped, mask):
		return PackedVector3Array()
	var out := PackedVector3Array()
	for i in range(_crumbs.size() - 1, -1, -1):
		var c := _crumbs[i]
		out.append(c)
		if _flat_dist(c, player.global_position) < CRUMB_SPACING_M:
			continue
		if BotDiagnosis.reaches(level, c, snapped, mask):
			return out
	return PackedVector3Array()


## A conversation: the talker's place first (its NPC when spawned, else the talker post, else the
## task's fallback position), then the dialogue with the outcome found node by node.
func _act_say(tick: int) -> void:
	var npc := str(task.get("npc", ""))
	var talker := _talker(npc)
	var where: Vector3 = task.get("pos", Vector3.INF)
	var reach := 3.5
	if talker != null:
		where = talker.global_position
		reach = talker.radius_m
	else:
		var n := _entity_node(npc)
		if n != null:
			where = n.global_position
	if not where.is_finite():
		where = _where(npc)
	var capsule := float(player.profile.get("capsule_radius_m", 0.85))
	if _flat_dist(player.global_position, where) > reach + capsule - TALK_SLACK_M or (talker == null and _entity_node(npc) == null):
		if _act_travel(tick, where, maxf(1.0, reach + capsule - TALK_SLACK_M - 0.5)) and talker == null and _entity_node(npc) == null:
			# at the place and nobody there yet (the talker's chunk part, the NPC's spawn): wait a little
			stop_moving()
		return
	stop_moving()
	if tick - _talk_tick < TALK_RETRY_TICKS:
		return
	_talk_tick = tick
	var dialogue := str(task.get("dialogue", ""))
	if talker != null and talker.resolved_dialogue_id() != "":
		dialogue = talker.resolved_dialogue_id()
	var speaker := talker.resolved_npc_id() if talker != null else npc
	var r := _say(dialogue, speaker, str(task.get("outcome", "")))
	run.metrics.note(tick, "say %s / %s -> %s: %s" % [speaker, dialogue, task.get("outcome", ""), r])
	_next_plan_tick = tick


## Starts `dialogue_id` with `npc_id` and takes, line by line, the choices that lead to the choice
## whose outcome is `outcome` (at most 8 lines); then ends it. {"ok": the outcome was taken, "node",
## "why"}.
func _say(dialogue_id: String, npc_id: String, outcome: String) -> Dictionary:
	var s := Quests.start_dialogue(dialogue_id, npc_id)
	if s == null:
		return {"ok": false, "why": "no dialogue"}
	run.metrics.note_screen("dialogue")
	run.metrics.note_dialogue_text(s.text())
	var reach := _outcome_nodes(GameData.get_record(dialogue_id), outcome)
	var taken := false
	var why := ""
	for i in 8:
		if not s.is_active():
			why = "ended"
			break
		var idx := s.find_choice(outcome)
		if idx >= 0:
			taken = bool(s.choose(idx).get("ok", false))
			run.metrics.note_dialogue_text(outcome, false)
			break
		var picked := -1
		for c: Dictionary in s.choices():
			if bool(c.get("locked", false)) or bool(c.get("implicit", false)):
				continue
			if str(c.get("next", "")) != "" and reach.has(str(c.next)):
				picked = int(c.index)
				break
		if picked < 0:
			why = "no way to %s from %s" % [outcome, s.node_id]
			break
		var before := s.node_id
		s.choose(picked)
		if s.is_active() and s.node_id != before:
			run.metrics.note_dialogue_text(s.text())
	var node := s.node_id if s.is_active() else ""
	Quests.end_dialogue()
	return {"ok": taken, "node": node, "why": why}


## The nodes of a dialogue record from which a choice with `outcome` can be reached (its own node and
## every node whose choices lead there).
static func _outcome_nodes(rec: Dictionary, outcome: String) -> Dictionary:
	var nodes: Array = rec.get("nodes", []) if typeof(rec.get("nodes")) == TYPE_ARRAY else []
	var reach := {}
	for n: Variant in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		for c: Variant in (n as Dictionary).get("choices", []):
			if typeof(c) == TYPE_DICTIONARY and str((c.get("effects", {}) as Dictionary).get("outcome", "")) == outcome:
				reach[str(n.id)] = true
	var grew := true
	while grew:
		grew = false
		for n: Variant in nodes:
			if typeof(n) != TYPE_DICTIONARY or reach.has(str(n.id)):
				continue
			for c: Variant in (n as Dictionary).get("choices", []):
				if typeof(c) == TYPE_DICTIONARY and reach.has(str(c.get("next", ""))):
					reach[str(n.id)] = true
					grew = true
					break
	return reach


## Breaks a prop by its world id: walk to it (its index position while its chunk is out), then the
## Valley's break act (lock it when it can be locked, close in, heavies). An engine is hurled at with
## Crag Hurl when it is ready and the engine stands in its range, until 8 s of hurling leave it
## unhurt (then blows for RANGED_IGNORE_S).
func _act_smash(tick: int, defending: bool) -> void:
	var id := str(task.get("id", ""))
	var prop := _world_node(id) as BreakableProp
	if prop == null or not prop.is_inside_tree():
		_act_travel(tick, _where(id), 12.0)
		return
	if prop.destroyed:
		_next_plan_tick = tick
		return
	if prop is SiegeEngine and _engine_hurl_ok(tick, prop) and _hurl_at_engine(tick, prop):
		return
	task["target"] = prop
	_act_break(tick, defending)


## Whether Crag Hurl at `engine` is still worth trying: in its band, ready, and not given up after
## RANGED_GIVE_UP_S of hurling that did not hurt it.
func _engine_hurl_ok(tick: int, engine: BreakableProp) -> bool:
	var d := _flat_dist(player.global_position, engine.global_position)
	if d < 12.0 or d > 40.0 or combat.ready_slot(BotCombat.BOULDER_HURL) == "":
		return false
	var e := engine.get_node_or_null("CombatEntity") as CombatEntity
	if e == null or e.combatant == null:
		return false
	var key := "hurl:" + str(engine.world_id)
	if int(_ignored.get(key, -1)) > tick:
		return false
	return not _ranged_futile(key, e.combatant.pools.health, tick)


## Crag Hurl (Boulder Hurl's evolution, a siege category) at an engine between 12 and 40 m: lock it
## when it can be locked, face it, hurl. True while hurling. Not at an engine the giant may not target
## (P03's hostile-only targeting: the war camp's engines while Aldmere is at peace - its lock is
## refused, and the bot pressed lock in front of the camp's catapult until the watchdog): the first
## blow at one is a melee one, an offence that turns Aldmere hostile.
func _hurl_at_engine(tick: int, engine: BreakableProp) -> bool:
	var d := _flat_dist(player.global_position, engine.global_position)
	if d < 12.0 or d > 40.0:
		return false
	var key := combat.ready_slot(BotCombat.BOULDER_HURL)
	if key == "" or player.controller.state != CombatController.State.LOCOMOTION:
		return false
	var e := engine.get_node_or_null("CombatEntity") as CombatEntity
	if e != null and e.combatant != null and e.combatant.lockable and not player.targeting.may_target(e):
		return false
	stop_moving()
	var locked := player.targeting.locked_entity()
	if e != null and e.combatant != null and e.combatant.lockable and locked != e:
		player.camera_rig.yaw = TargetingRules.yaw_of(_flat(engine.global_position - player.global_position))
		if tick % 8 == 0:
			player.router.inject_edge(&"lock_press")
		return true
	player.camera_rig.yaw = TargetingRules.yaw_of(_flat(engine.global_position - player.global_position))
	combat.use_slot(key, "crag hurl at %s" % engine.world_id)
	return true


## A LevelExit: walk to it and press interact.
func _act_exit(tick: int) -> void:
	var id := str(task.get("id", ""))
	var exit: Node3D = null
	for n in get_tree().get_nodes_in_group("level_exits"):
		if "exit_id" in n and str(n.get("exit_id")) == id:
			exit = n
	if exit == null:
		var idx := level.index() if level != null else null
		var p := idx.position_of(id) if idx != null else Vector3.INF
		_act_go(tick, p, 3.0)
		return
	task["target"] = exit
	_act_interact(tick)


# ---- the Iron Regiment (the crown's breach)

## The battle in Fort Aldmere's bailey: through the broken gate into the bailey (its engage trigger
## closes the portcullis and starts the Wall), then the battle's units: the engines' crews and the
## inner ballistae first (they shoot; their crews are units of the Wall, whose fall begins the Charge),
## then whatever unit of the battle is nearest; Corvane's yield is decided by the screens' hook.
## The gate bastions' two ballistae stand 16 m above the bailey, out of melee reach, and deal most of
## the battle's damage (the first crown run died to them standing in the bailey with nothing left in
## reach): while one still shoots, a ready Crag Hurl is thrown at it from 14-38 m and a ready Runic
## Bolt at a crew member serving it (_battle_ranged); between the cooldowns the melee goes on.
func _act_battle(tick: int, defending: bool) -> void:
	if str(WorldState.get_flag("boss.corvane.outcome", "")) != "":
		_next_plan_tick = tick
		return
	var bailey := _where("world.marker.fort_bailey")
	if _battle_ranged(tick):
		return
	var target := _battle_target()
	if target is EnemyActor:
		mode = "combat"
		combat.fight(tick, target as EnemyActor)
		return
	if target is BreakableProp:
		task["target"] = target
		if target is SiegeEngine and _hurl_at_engine(tick, target as BreakableProp):
			return
		_act_break(tick, defending)
		return
	_act_travel(tick, bailey, 10.0)


## The fort's elevated ballistae (on the gate bastions) that may still shoot, nearest first.
func _elevated_fort_engines() -> Array[SiegeEngine]:
	var out: Array[SiegeEngine] = []
	for n in get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		var s := n as SiegeEngine
		if s == null or not s.is_inside_tree() or not s.can_shoot() \
				or not str(s.world_id).begins_with("world.aldmere.fort_ballista"):
			continue
		if s.global_position.y - player.global_position.y > combat.elevated_m():
			out.append(s)
	out.sort_custom(func(a: SiegeEngine, b: SiegeEngine) -> bool:
		return _flat_dist(a.global_position, player.global_position) < _flat_dist(b.global_position, player.global_position))
	return out


## A ranged blow at an elevated fort ballista that still shoots: Crag Hurl at the engine (from 14-38 m;
## the giant steps to 26 m on the bailey's side when it stands nearer or farther), else Runic Bolt at a
## crew member serving it. True while one is being thrown or the giant takes its place for it.
func _battle_ranged(tick: int) -> bool:
	if player.controller.state != CombatController.State.LOCOMOTION or combat.defend_busy(tick):
		return false
	var hurl := combat.ready_slot(BotCombat.BOULDER_HURL) != ""
	var bolt := combat.ready_slot(BotCombat.RUNIC_BOLT) != ""
	if not hurl and not bolt:
		return false
	for s in _elevated_fort_engines():
		# One engine at a time, the nearest: the hurl at it (unless given up), then a bolt at its crew.
		var hurl_key := "hurl:" + (s.entity.entity_id if s.entity != null else str(s.world_id))
		if hurl and int(_ignored.get(hurl_key, -1)) <= tick:
			var d := _flat_dist(s.global_position, player.global_position)
			if d < 14.0 or d > 38.0:
				var bailey := _where("world.marker.fort_bailey")
				var away := _flat(bailey - s.global_position)
				if away.length_squared() < 1.0:
					away = Vector3.BACK
				_act_go(tick, s.global_position + away.normalized() * 26.0, 3.0)
				return true
			if not _ranged_futile(hurl_key, s.entity.combatant.pools.health, tick) and _hurl_at_engine(tick, s):
				return true
		if bolt:
			for c in s.crew():
				var e := c as EnemyActor
				if e != null and s.serves(e) and not _is_ignored(e) \
						and _flat_dist(e.global_position, player.global_position) <= 40.0 \
						and not _ranged_futile(e.entity.entity_id, e.entity.combatant.pools.health, tick):
					mode = "combat"
					combat.fight(tick, e)
					return true
		break
	return false


## The battle's next target: a crew of an engine within 70 m (or the engine itself when it is
## uncrewed and still shoots), else the nearest living unit of the battle's encounters, else null.
func _battle_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for enc: String in ["encounter.aldmere_iron_regiment_wall", "encounter.aldmere_iron_regiment_charge",
			"encounter.aldmere_iron_regiment_stand", "encounter.aldmere_fort_gate"]:
		for e in _encounter_alive(enc):
			if not combat.is_threat(e) or _is_ignored(e):
				continue
			var d := _flat_dist(e.global_position, player.global_position)
			if str(e.entity.combatant.base_record.get("role", "")) == "crew":
				d *= 0.5   # the crews first: their engines deal most of the battle's damage
			if combat.is_elevated(e):
				continue
			if d < best_d:
				best = e
				best_d = d
	for n in get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		var s := n as SiegeEngine
		if s == null or s.destroyed or not s.is_inside_tree() or not str(s.world_id).begins_with("world.aldmere.fort_ballista"):
			continue
		var d := _flat_dist(s.global_position, player.global_position) * 0.7
		if s.global_position.y - player.global_position.y > combat.elevated_m():
			continue
		if d < best_d:
			best = s
			best_d = d
	return best


# ---- the Troll Matriarch

## The den: the Matriarch fought in her bowl. Slay: she is fought to the end, each brazier broken while
## she stands within BRAZIER_BURN_M of it (8 s of Burning: no regeneration; F37: fire matters at stage
## 4). Drive (P35): her flight needs the den's flags - the three nests burned (a brazier beside each:
## broken, its fire burns the nest) and the back wall open (the woodfolk open it 20 s after the last
## nest) - and her health at or below 60 %: the braziers first, then she is fought while above
## DRIVE_HOLD_FRAC (else only defended against, her whelps fought) until the wall opens, then fought
## down until she runs for the exit (not struck while she runs: a fleeing boss is no threat).
func _act_matriarch(tick: int, defending: bool) -> void:
	var res := str(task.get("resolution", "slay"))
	var m := _entity_node("world.greywood.troll_matriarch") as EnemyActor
	if m == null or not m.entity.is_alive():
		_act_travel(tick, _where("world.marker.troll_den"), 8.0)
		return
	if res == "drive":
		_act_drive(tick, defending, m)
		return
	var brazier := _brazier_near(m.global_position)
	if brazier != null:
		task["target"] = brazier
		_act_break(tick, defending)
		return
	mode = "combat"
	combat.fight(tick, m)


func _act_drive(tick: int, defending: bool, m: EnemyActor) -> void:
	if m.has_method("is_fleeing") and bool(m.call("is_fleeing")):
		_fight_others(tick, m)
		return
	if not QuestConditions.truthy(WorldState.get_flag("world.troll_den.nests_burned")):
		var b := _nearest_brazier()
		if b != null:
			task["target"] = b
			_act_break(tick, defending)
			return
	var frac := m.entity.combatant.pools.ratio("health")
	if not QuestConditions.truthy(WorldState.get_flag("world.troll_den.wall_open")) and frac <= DRIVE_HOLD_FRAC:
		_fight_others(tick, m)
		return
	mode = "combat"
	combat.fight(tick, m)


## Fights the nearest threat other than `boss` (her whelps); with none, stands and defends.
func _fight_others(tick: int, boss: EnemyActor) -> void:
	for e: EnemyActor in combat.threats(combat.engage_radius()):
		if e != boss and not _is_ignored(e):
			mode = "combat"
			combat.fight(tick, e)
			return
	stop_moving()
	mode = "combat"
	combat.defend(tick)


func _brazier_near(at: Vector3) -> BreakableProp:
	for id: String in ["world.greywood.den_brazier_1", "world.greywood.den_brazier_2", "world.greywood.den_brazier_3"]:
		if WorldState.is_destroyed(id):
			continue
		var b := _world_node(id) as BreakableProp
		if b != null and not b.destroyed and _flat_dist(b.global_position, at) <= BRAZIER_BURN_M:
			return b
	return null


func _nearest_brazier() -> BreakableProp:
	var best: BreakableProp = null
	var best_d := INF
	for id: String in ["world.greywood.den_brazier_1", "world.greywood.den_brazier_2", "world.greywood.den_brazier_3"]:
		if WorldState.is_destroyed(id):
			continue
		var b := _world_node(id) as BreakableProp
		if b == null or b.destroyed:
			continue
		var d := _flat_dist(b.global_position, player.global_position)
		if d < best_d:
			best = b
			best_d = d
	return best


# ---- Harrok

## The champion's duel: into the Moot's ring (its engage area), then Harrok fought until he yields (the
## screens' hook decides: spare, or strike and fight him to the death).
func _act_duel(tick: int) -> void:
	var h := _entity_node("world.stonehold.harrok") as EnemyActor
	if h != null and h.entity.is_alive() and not bool(h.get("yielded")) and combat.is_threat(h):
		mode = "combat"
		combat.fight(tick, h)
		return
	if h != null and h.entity.is_alive() and not bool(h.get("yielded")):
		# not aware yet: step into the ring toward him
		_act_travel(tick, h.global_position, 12.0)
		return
	_act_travel(tick, _where("world.marker.moot_ring"), 10.0)


# --------------------------------------------------------------------------- lookups

## The position of `id`: a spawned entity, a loaded node with that world id, the index (checkpoints,
## markers, areas, POIs, exits, props, encounter centres), an encounter record's spawn; else INF.
func _where(id: String) -> Vector3:
	if id == "":
		return Vector3.INF
	var e := _entity_node(id)
	if e != null:
		return e.global_position
	var n := _world_node(id)
	if n != null:
		return n.global_position
	var idx := level.index() if level != null else null
	if idx == null:
		idx = WorldIndex.for_level(WORLD_LEVEL)
	if idx != null:
		var p := idx.position_of(id)
		if p.is_finite():
			return p
	return _spawn_position(id)


## A loaded node whose world id (or interact id, or name) is `world_id`: props, interactables, forges,
## shrines, engines (cached while it stays in the tree).
func _world_node(world_id: String) -> Node3D:
	if world_id == "" or not is_inside_tree():
		return null
	var ref: Variant = _node_cache.get(world_id)
	if ref is WeakRef:
		var n := (ref as WeakRef).get_ref() as Node3D
		if n != null and n.is_inside_tree():
			return n
	var name_key := world_id.validate_node_name()
	for group: String in ["breakables", "interactables", "forges", Shrine.GROUP, SiegeEngine.GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var n := node as Node3D
			if n == null or not n.is_inside_tree():
				continue
			if ("world_id" in n and str(n.get("world_id")) == world_id) or ("interact_id" in n and str(n.get("interact_id")) == world_id \
					and not (n is NpcTalker)) or str(n.name) == name_key:
				_node_cache[world_id] = weakref(n)
				return n
	return null


## The NpcTalker that speaks for `id`: an NPC's (its resolved npc id), or a talker post named `id`.
func _talker(id: String) -> NpcTalker:
	var name_key := id.validate_node_name()
	var by_npc: NpcTalker = null
	for node in get_tree().get_nodes_in_group("interactables"):
		var t := node as NpcTalker
		if t == null or not t.is_inside_tree() or not t.enabled:
			continue
		var host := t.get_parent()
		if str(t.name) == name_key or (host != null and str(host.name) == name_key):
			return t
		if t.resolved_npc_id() == id and by_npc == null:
			by_npc = t
	return by_npc


## Where an encounter record spawns `entity_id` (its spawn's position, else its centre): INF if none.
func _spawn_position(entity_id: String) -> Vector3:
	if _spawn_positions.is_empty():
		for rec: Dictionary in GameData.records_of_type("encounter"):
			if str(rec.get("level", "")) != WORLD_LEVEL:
				continue
			var c: Variant = rec.get("center_m")
			for sp: Variant in rec.get("spawns", []):
				if typeof(sp) != TYPE_DICTIONARY:
					continue
				var p: Variant = sp.get("position_m", c)
				if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
					_spawn_positions[str(sp.get("entity_id", ""))] = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return _spawn_positions.get(entity_id, Vector3.INF)


func _prop(world_id: String) -> Node3D:
	if not _in_world():
		return super(world_id)
	return _world_node(world_id)


# --------------------------------------------------------------------------- watchdogs, invariants, breaches

func _watchdogs(tick: int) -> void:
	if _valley_part():
		super(tick)
		return
	var key := _watch_key()
	if key != run.obj_key:
		run.obj_key = key
		run.obj_ticks = 0
		run.obj_deaths = 0
		run.stuck_level = 0
		wrun.stage_limit_s = _stage_limit(key)
		print("[world_bot] %.1f s  %s  stage %d  level %d  %s  limit %.0f s" % [float(tick - run.started_tick) / 60.0, key,
			player.current_growth_stage(), int(player.progression.level) if player.progression != null else 0,
			wrun.preset, wrun.stage_limit_s])
	run.obj_ticks += 1
	if run.obj_ticks > ActionDef.seconds_to_ticks(wrun.stage_limit_s):
		_breach("timeout", "%s took more than %d s (tick %d)" % [key, int(wrun.stage_limit_s), tick])


## The watchdog's key: the main thread's stage, and during the oaths the current oath quest's stage.
func _watch_key() -> String:
	var stage := Quests.stage_of(WORLD_MAIN)
	var key := "%s:%s" % [WORLD_MAIN, stage]
	if stage == "oaths" or (stage == "grow6" and wrun.oath_count >= 3 and oaths_done() < 3):
		for pair: Array in wrun.oaths:
			var q := str(OATH_QUESTS[pair[0]])
			if Quests.quest_state(q) == Quests.ACTIVE:
				key += "/%s:%s" % [q, Quests.stage_of(q)]
				break
		if _can_grow5():
			key += "/grow5"
	elif stage == "grow6" and player.current_growth_stage() < 5:
		key += "/grow5"
	return key


## The stage's watchdog limit: 300 s, 600 s for a boss stage (the den, the battle, the champion), 900 s
## for the oaths' other stages; plus the road route to the stage's goal at TRAVEL_ALLOWANCE_MPS.
func _stage_limit(key: String) -> float:
	var base := STAGE_TIMEOUT_S
	if key.contains("quest.oath_wood:den") or key.ends_with(":champion") \
			or (key.contains("quest.oath_crown:resolve") and _resolution_of("crown") == "breach"):
		base = BOSS_STAGE_TIMEOUT_S
	elif key.contains("/quest.oath_"):
		base = OATHS_TIMEOUT_S
	var goal := _stage_goal()
	var travel := 0.0
	if goal.is_finite() and route != null and route.index != null:
		var rp := BotRoute.road_path(route.index, player.global_position, goal, player.current_growth_stage())
		travel = maxf(float(rp.length), _flat_dist(player.global_position, goal))
	wrun.stage_route_m = travel
	return base + travel / TRAVEL_ALLOWANCE_MPS


func _stage_goal() -> Vector3:
	var p: Variant = task.get("pos", Vector3.INF)
	if p is Vector3 and (p as Vector3).is_finite():
		return p
	var o := Quests.objective_for(WORLD_MAIN)
	var op: Variant = o.get("position", Vector3.INF)
	return op if op is Vector3 else Vector3.INF


func _resolution_of(oath: String) -> String:
	for pair: Array in wrun.oaths:
		if pair[0] == oath:
			return str(pair[1])
	return ""


func _breach(reason: String, detail: String, goal := Vector3.INF) -> void:
	if _valley_part() or not _in_world():
		super(reason, detail, goal)
		return
	var o := Quests.objective_for(WORLD_MAIN)
	var g := goal
	if not g.is_finite():
		g = _stage_goal()
	var diag := BotDiagnosis.diagnose_world(o, player, level, reason, g, 12.0, _crumbs, _nav_mask())
	diag["detail"] = detail
	diag["task"] = str(task.get("kind", ""))
	diag["policy"] = wrun.preset
	diag["oaths"] = wrun.oaths.slice(0, wrun.oath_count)
	diag["watch_key"] = run.obj_key
	diag["route"] = (diag.get("route", {}) as Dictionary)
	(diag.route as Dictionary)["bot_route"] = route.describe() if route != null else ""
	run.breaches.append(diag)
	run.metrics.note(Sim.tick, "breach %s: %s (%s)" % [reason, detail, diag.classification])
	print("[world_bot] breach %s: %s -> %s" % [reason, detail, diag.classification])
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
	if _in_world() and wrun != null:
		# The world's budget rule replaces the Valley's count check (_watch_budget).
		var kept := PackedStringArray()
		for f in fails:
			if not f.begins_with(BotDiagnosis.BUDGET_FAILURE_PREFIX):
				kept.append(f)
		fails = kept
		fails.append_array(wrun.budget_failures)
		wrun.budget_failures.clear()
		_budget_tick()
		fails.append_array(BotDiagnosis.check_world_invariants(get_tree(), _world, wrun.invariant_state,
			wrun.metrics.save_bytes_max, tick % 30 == 0))
	if fails.is_empty():
		return
	for f in fails:
		run.invariant_failures.append({"tick": tick, "failure": f})
		print("[world_bot] invariant failed: %s" % f)
	_finish("invariant")


# --------------------------------------------------------------------------- the result

## AUTOPILOT_RESULT's "world_bot": the Valley bot's result (the metrics, breaches with their world
## diagnoses, invariant failures, notes) plus the world's (WorldMetrics), the policy and the outcomes.
static func result(tick: int) -> Dictionary:
	if run == null:
		return {}
	var out := ValleyBot.result(tick)
	var w := run.world as WorldRun
	if w == null:
		return out
	out["world"] = w.metrics.result() if w.metrics != null else {}
	out["policy"] = {"preset": w.preset, "oaths": w.oaths.slice(0, w.oath_count), "oath_count": w.oath_count,
		"champion": w.champion, "corvane": w.corvane, "ancestry": w.ancestry, "explore": w.explore, "campaign": w.campaign,
		"until": w.until_flag}
	out["outcomes"] = _outcomes()
	out["budget"] = {"max_counted": w.max_counted, "over_cap_s": snappedf(w.over_cap_ticks / 60.0, 0.01)}
	out["yields_decided"] = w.decided.duplicate(true)
	out["campaign_completed"] = Quests.is_complete(WORLD_MAIN) or QuestConditions.truthy(WorldState.get_flag("campaign.completed", false))
	out["completed"] = bool(out.get("completed", false)) or bool(out.campaign_completed)
	out["main_stage"] = Quests.stage_of(WORLD_MAIN)
	return out


static func _outcomes() -> Dictionary:
	var out := {}
	for oath: String in OATHS:
		out[oath] = str(WorldState.get_flag("oath.%s.outcome" % oath, ""))
	for b: String in ["matriarch", "corvane", "harrok"]:
		out["boss." + b] = str(WorldState.get_flag("boss.%s.outcome" % b, ""))
	out["skarn"] = "saved" if QuestConditions.truthy(WorldState.get_flag("world.skarn.saved")) else (
		"burned" if QuestConditions.truthy(WorldState.get_flag("world.skarn.burned")) else "")
	out["throne"] = QuestConditions.truthy(WorldState.get_flag("world.throne.claimed"))
	out["ancestry"] = str(WorldState.get_flag("ancestry.chosen", ""))
	return out


func trace_line(tick: int) -> String:
	var line := super(tick).replace("[valley_bot trace]", "[world_bot trace]")
	if _in_world() and route != null:
		line += "  | %s  region %s" % [route.describe(), _world.region_id]
	return line
