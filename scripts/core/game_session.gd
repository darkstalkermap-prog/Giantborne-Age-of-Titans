extends Node
## Game session (autoload "GameSession", plan §2.9, §3.6, decisions 13-15): the game mode, the
## live character state, the last checkpoint document, and the flows between them - title,
## New Game, Continue, the sandbox, checkpoints, death and reload. Autoload order: Events,
## GameData, Settings, WorldState, GameSession, (Quests,) Sim.
##
## Modes. TITLE shows the title screen only. SANDBOX loads the M1 sandbox (or the --level
## scene) with the player record as it is; resets clear the world (WorldState.clear) and reload.
## VALLEY is the campaign (P20, plan M6-M9 decision 11: the Valley and the world; is_campaign()
## is its alias): it loads the campaign level `level_id` (or the --level scene) with `character`
## applied; it never clears the world on death but reloads the last checkpoint. Every mode change
## and reload is a reload of main.tscn: main.gd builds what `mode` asks for and calls
## on_level_ready(level, player).
##
## Checkpoints exist only when checkpoints_enabled() (the campaign, or a test level that sets
## test_checkpoints). Triggers (GameSession listens to the events; nothing calls it directly):
##   checkpoint_reached (a shrine's first activation, a waystone)   -> respawn: that marker
##   shrine_activated, shrine_rested, ui_screen_requested("shrine")  -> respawn: that shrine
##   growth_changed for the player beside a shrine                   -> respawn: that shrine
##   talent_learned, ancestry_chosen, attributes_changed,
##     loadout_changed while a shrine's screen is open (M8 gate)     -> respawn: that shrine
##   boss_defeated (in the Valley)                                   -> respawn: valley.shrine.kingsfall
##   boss_disengaged "fled" (a drive-out, M8 gate)                   -> respawn unchanged
##   boss_disengaged "yielded_talk" (Harrok's talk ending ends his
##     engaged duel, M8 release)                                     -> respawn unchanged
##   quest_stage_changed for quest.main                              -> respawn unchanged
## A request waits (one pending request; a later one replaces the reason and keeps the newest
## respawn) while checkpoint_blockers() is not empty: the player is dead, grabbed, executing or
## holding something, a modal screen is open, a boss fight or battle is engaged (M8 release, R1), or
## an enemy within 40 m is aware of the player.
## It is retried every tick from a Sim POST_RESOLVE hook (order 200). The shrine screen's
## checkpoint is taken at once, before the screen opens; M8 gate (F15): what the giant then makes
## of itself in that screen (talents, the ancestry, attribute points, the loadout - the screens call
## the first three permanent) takes the shrine's checkpoint again at once, at most once a frame, the
## shrine's own screens not holding it back (the game is paused, as it was when the screen opened;
## anything else that holds a checkpoint back still does). Only the campaign writes the save slot
## (and only with `persist`); a test level's checkpoints in the sandbox stay in memory. A reached
## checkpoint also sets the flag visited.<checkpoint id> (fast travel and respawns, P20).
##
## Death in the campaign: main shows "Enter / A: load last checkpoint" and emits
## reload_checkpoint_requested("death"): the checkpoint's world and character come back, the
## resources are raised to progression.default.death_reload_floor (health 60 %, stamina 100 %,
## essence 50 %; fury 0), and the scene reloads. Continue restores a save exactly.
##
## The campaign across levels (P20, plan M6-M9 §2.6):
##   * travel_to(level, checkpoint, reason) - from a LevelExit (Events.travel_requested), the map
##     (fast travel, P27) or the bots - commits a checkpoint document whose "level" is the
##     destination and whose respawn is the destination's checkpoint, emits level_leaving and
##     reloads main.tscn. It is refused with a reason: the checkpoint blockers (an exit ignores
##     aware enemies; fast travel ignores the map screen it comes from), a destination whose index
##     max_stage is below the giant's stage, and for fast travel a checkpoint not yet visited, whose
##     requires_flags do not hold, or (M7 gate) whose respawn blockers refuse it - arriving is a
##     respawn there.
##   * respawn_transform(id): the checkpoint's node when it is loaded, else its world index entry
##     (WorldIndex), so a respawn in a streamed-out chunk still lands. respawn_checkpoint(): the
##     saved respawn unless a blocker refuses it (built in: its index max_stage below the stage;
##     registered: register_respawn_blocker), else the nearest visited, unblocked checkpoint; a
##     load that moves the respawn so says why and where on the HUD (M7 gate).
##   * activated_this_visit / mark_activated: shrines and waystones activate once per level visit
##     (a load of a level is a visit), not once per node.
##   * level_entered(tick, level, reason) once the level is ready (its is_ready() when it has one,
##     and Audio.is_ready() when the Audio autoload has one).
##   * progress: {"prologue_complete", "world_entered", "levels_visited", "tracked_quest"} in the
##     save (schema 2); the tracked quest is Quests.tracked_quest_id once P27 adds it.
##   * --mode=world starts the campaign in level.world with progression.default's world_start
##     character, inventory and flags; --start=<checkpoint> starts a New Game at that checkpoint.
##
## M8 release (R1, the release check's blocker): no checkpoint is committed while a boss fight or a battle is
## engaged (engaged_fights(): an engaged BossArena or BattleBoss; the blocker "fight:<boss id>", which holds
## completion requests too, a quit to the title's commit of one and travel). A request made before or during
## the fight waits until it is won (its own end - boss_defeated, a drive-out, Harrok's talk ending - is then
## taken with it), lost (a death reload drops it with the fight), abandoned or reset (the disengage rule). The
## Iron Regiment's battle had a request deferred from before it (waiting for no aware enemy within 40 m)
## committed as the Wall fell: the save held a battle not won with its Wall cleared, and after a death or a
## quit and Continue the giant was shut in an empty bailey. BattleBoss now also starts every engagement afresh
## and repairs such saves as they load (P34.md, "M8 release").
##
## Tests: reset_for_tests() (ResetHooks.BEFORE_EACH) puts the session in the sandbox, turns
## writes off, points SaveSlots at user://test_saves/ and replaces scene reloads with a log
## (scene_reloads), so a test drives the flow and instantiates the level itself.

enum Mode { TITLE, SANDBOX, VALLEY }

const MODE_NAMES := ["title", "sandbox", "valley"]
## The --mode values (P20: "world" starts the campaign in level.world from world_start).
const CLI_MODES := ["title", "sandbox", "valley", "world"]
const SANDBOX_SCENE := "res://scenes/world/sandbox_arena.tscn"
const VALLEY_LEVEL_ID := "level.valley"
## The open world's level record (P25 ships it; P20 plans for it).
const WORLD_LEVEL_ID := "level.world"
const PROGRESSION_ID := "progression.default"
const PLAYER_ID := "player.giant"
const MAIN_QUEST_ID := "quest.main"
## The world's main quest (P29: it leads once the prologue is done) and the oaths' quest ids
## (OathRules.OATH_QUEST_PREFIX): their progress is checkpointed as completion requests (fix-up 1).
const WORLD_MAIN_QUEST_ID := "quest.world_main"
const OATH_QUEST_PREFIX := "quest.oath_"
const KINGSFALL_RESPAWN := "valley.shrine.kingsfall"
## Where a save from a level this build does not have continues in the Valley (P26 places it;
## until then the Valley's start checkpoint is used).
const VALLEY_RETURN_CHECKPOINT := "valley.cp.kings_door"
## An aware enemy this close to the player defers a checkpoint (decision 13).
const AWARE_BLOCK_RADIUS_M := 40.0
## growth_changed counts as "growth at a shrine" when a shrine is at most this far away.
const SHRINE_GROWTH_RADIUS_M := 25.0
const HOOK_ORDER := 200
const TEST_SAVE_PATH := "user://test_saves/valley_1.json"
const DEFAULT_DEATH_FLOOR := {"health": 0.6, "stamina": 1.0, "essence": 0.5}
const VALLEY_MISSING := "Valley not built yet"
const WORLD_MISSING := "The Old Kingdom is not in this build"
## checkpoint_saved messages for a checkpoint that was taken but not written.
const NO_SAVING := "saving is off"
const MEMORY_ONLY := "kept in memory"
const MAX_RELOAD_LOG := 64
## travel_to's reasons (Events.travel_requested).
const TRAVEL_REASONS := ["exit", "fast_travel", "debug", "bot"]
## level_entered's reasons.
const ENTER_REASONS := ["new_game", "continue", "death", "travel", "fast_travel", "debug"]
## The refusal of a checkpoint above its arrival limit (plan M6-M9 §2.6).
const NARROW_PATHS := "The old paths here are too narrow for you now."
const NOT_VISITED := "You have not been there yet."
const NOT_OPEN := "The way there is not open yet."
const UNKNOWN_PLACE := "That place is not on the map."
## M8 release (R1): checkpoint_blockers()' code of an engaged boss fight or battle ("fight:<boss id>") and the
## line a travel it holds back is refused with.
const FIGHT_BLOCKER_PREFIX := "fight:"
const FIGHT_BLOCKED := "Not in the middle of a fight."
## boss_disengaged's reasons that end a fight (not "left": the boss resets) -> the reason of the fight's end
## checkpoint (M8 gate F38: the drive-out; M8 release R1: Harrok's talk ending in an engaged duel).
const BOSS_END_REASONS := {"fled": "boss_fled", "yielded_talk": "boss_yielded_talk"}
## The flag of a reached checkpoint (fast-travel eligibility, the respawn fallback).
const VISITED_PREFIX := "visited."
## level_entered waits at most this many frames for the level and the samples (then it is sent
## anyway, with a warning, so a stuck loader never hides the event).
const ENTER_WAIT_FRAMES := 1200

var mode: int = Mode.SANDBOX
## A scene that replaces the mode's level (--level=res://...tscn; tests).
var level_override := ""
## The campaign level being played (the save's "level"): a level record id, or a test level's
## scene path. "" outside the campaign.
var level_id := ""
## The live character state (CharacterState): applied by on_level_ready, refreshed from the
## player at every checkpoint.
var character: Dictionary = {}
## The last checkpoint document (the save format); {} = none yet.
var checkpoint_doc: Dictionary = {}
## The next on_level_ready restores `character` (and moves the player to respawn_id).
var pending_restore := false
## Write the save slot (false with --no-user-settings unless --save-dir is given, and in tests).
var persist := true
## The last shrine or waystone reached: where the next reload puts the player.
var respawn_id := ""
## A test level opts in to checkpoints outside the Valley (its root sets this while it exists).
var test_checkpoints := false
var stats := {"deaths": 0, "checkpoint_loads": 0, "play_time_s": 0.0}
## The campaign's progress (save schema 2): prologue_complete, world_entered, levels_visited,
## tracked_quest.
var progress: Dictionary = {}

## False in tests: reloads are only logged in scene_reloads (the test runner is the scene).
var allow_scene_reload := true
## The reason of every scene reload requested (new_game, continue, death, title, travel, ...).
var scene_reloads: Array[String] = []
## The result of the last mode_change_requested ({"ok", "message"}); the title screen reads it.
var last_mode_result: Dictionary = {}
## The result of the last travel_requested ({"ok", "message"}).
var last_travel_result: Dictionary = {}
## How many checkpoints were committed (this process).
var checkpoints_taken := 0
## The message of the last Continue read ("Recovered ...", dropped ids), "" when clean.
var last_load_message := ""
## level_entered events sent (this process): [{"tick", "level", "reason"}] (tests, debug).
var entered_log: Array = []

var _configured := false
## The --level scene of the command line ("" = none). A Continue may replace level_override with
## its save's scene; quitting to the title, the sandbox and a New Game go back to this one (P16).
var _cli_level_override := ""
## The --start checkpoint of the command line ("" = none).
var _cli_start := ""
var _pending: Dictionary = {}       ## {"reason", "respawn", "tick"} of the queued checkpoint
var _load_reason := ""              ## why pending_restore is set: new_game|continue|death|debug|menu|travel|fast_travel
var _reload_floor: Dictionary = {}  ## death_reload_floor to apply on the next restore
var _restoring := false             ## inside on_level_ready (growth events there are not growth)
var _reload_queued := false
var _player_ref: WeakRef = null
var _level_ref: WeakRef = null
## A New Game starts at this checkpoint instead of the scene's Player node ("" = none).
var _start_override := ""
## Checkpoints (shrines, waystones) activated during this level visit.
var _visit_activated: Dictionary = {}
## Callable(checkpoint_id: String) -> String, "" = fine (register_respawn_blocker).
var _respawn_blockers: Array[Callable] = []
## The level whose checkpoint the respawn blockers judge while respawn_blocker() asks them for
## another level than the save's (a fast travel's destination); "" = the save's level.
var _blocker_level := ""
## The level_entered waiting for its level and the samples: {"level": WeakRef, "level_id",
## "reason", "frames"}; {} when none waits.
var _entering: Dictionary = {}
## M8 gate (F15): a shrine-screen choice's checkpoint is queued for the end of this frame.
var _shrine_choice_queued := false


func _ready() -> void:
	add_to_group("debug_info_providers")
	configure_from_args(OS.get_cmdline_user_args())
	Events.checkpoint_reached.connect(_on_checkpoint_reached)
	Events.shrine_activated.connect(_on_shrine_activated)
	Events.shrine_rested.connect(_on_shrine_rested)
	Events.ui_screen_requested.connect(_on_ui_screen_requested)
	Events.growth_changed.connect(_on_growth_changed)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.boss_disengaged.connect(_on_boss_disengaged)
	Events.quest_stage_changed.connect(_on_quest_stage_changed)
	Events.quest_started.connect(_on_quest_started)       # M8 gate fix-up 1 (N4.2)
	Events.quest_completed.connect(_on_quest_completed)
	# M8 gate (F15): what the giant makes of itself in a shrine's screen.
	Events.talent_learned.connect(_on_shrine_choice_2)
	Events.ancestry_chosen.connect(_on_shrine_choice_2)
	Events.attributes_changed.connect(_on_shrine_choice_1)
	Events.loadout_changed.connect(_on_shrine_choice_2)
	Events.reload_checkpoint_requested.connect(_on_reload_checkpoint_requested)
	Events.mode_change_requested.connect(_on_mode_change_requested)
	Events.entity_died.connect(_on_entity_died)
	Events.travel_requested.connect(_on_travel_requested)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_post_resolve, HOOK_ORDER)


# --------------------------------------------------------------------------- command line

## Reads the command-line options once per process (later calls do nothing); see parse_args.
func configure_from_args(args: PackedStringArray) -> void:
	if _configured:
		return
	_configured = true
	apply_args(parse_args(args))


## The session options in `args` (the user args after "--"):
##   --mode=title|sandbox|valley|world  default title; without --mode: valley with --new-game or
##                                 --continue, else sandbox when --autoplay, --scenario or --level
##                                 is given (so the M1 tools keep booting the sandbox). world (P20)
##                                 is the campaign starting in level.world from world_start.
##   --new-game / --continue       how --mode=valley starts (neither: continue when a save
##                                 loads, else a new game); --mode=world --continue continues
##   --start=<checkpoint id>       a New Game starts at that checkpoint (debug, tests, web checks)
##   --level=res://...tscn         the level scene to load instead of the mode's own
##   --save-dir=user://...         the folder of the save slot (keeps saving on with
##                                 --no-user-settings)
##   --no-user-settings            no writes to the player's files (persist false)
## Returns {"mode", "mode_given", "new_game", "continue", "level", "save_dir", "start",
## "no_user_settings", "tool_run", "persist", "unknown_mode"}.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"mode": "title", "mode_given": false, "new_game": false, "continue": false,
		"level": "", "save_dir": "", "start": "", "no_user_settings": false, "tool_run": false,
		"unknown_mode": ""}
	for arg in args:
		if arg.begins_with("--mode="):
			out.mode = arg.substr(7).strip_edges().to_lower()
			out.mode_given = true
		elif arg == "--new-game":
			out.new_game = true
		elif arg == "--continue":
			out["continue"] = true
		elif arg.begins_with("--level="):
			out.level = arg.substr(8).strip_edges()
		elif arg.begins_with("--save-dir="):
			out.save_dir = arg.substr(11).strip_edges()
		elif arg.begins_with("--start="):
			out.start = arg.substr(8).strip_edges()
		elif arg == "--no-user-settings":
			out.no_user_settings = true
		elif arg.begins_with("--autoplay=") or arg.begins_with("--scenario="):
			out.tool_run = true
	if not out.mode_given:
		if out.new_game or out["continue"]:
			out.mode = "valley"
		elif out.tool_run or out.level != "":
			out.mode = "sandbox"
	if not (str(out.mode) in CLI_MODES):
		out.unknown_mode = out.mode
		out.mode = "title"
	out["persist"] = not out.no_user_settings or out.save_dir != ""
	return out


## Applies parse_args() options to the session (no scene reload: main.tscn is not loaded yet
## when this runs at start-up).
func apply_args(o: Dictionary) -> void:
	persist = bool(o.get("persist", true))
	if str(o.get("save_dir", "")) != "":
		SaveSlots.path_override = str(o.save_dir).path_join(SaveSlots.SLOT + ".json")
	var level := str(o.get("level", ""))
	if level != "":
		if ResourceLoader.exists(level):
			level_override = level
			_cli_level_override = level
		else:
			push_warning("GameSession: --level=%s does not exist; ignored" % level)
	_cli_start = str(o.get("start", ""))
	if str(o.get("unknown_mode", "")) != "":
		push_warning("GameSession: unknown --mode=%s (title | sandbox | valley | world); showing the title" % o.unknown_mode)
	match str(o.get("mode", "title")):
		"sandbox":
			mode = Mode.SANDBOX
		"valley":
			# Continue needs the save's level; New Game needs the Valley (or the --level scene).
			if bool(o.get("continue", false)):
				var r := _begin_continue()
				if not r.ok:
					push_warning("GameSession: --continue failed (%s); showing the title" % r.message)
					mode = Mode.TITLE
			elif bool(o.get("new_game", false)) or not _begin_continue().ok:
				if valley_available():
					_begin_new_valley(_cli_start)
				else:
					push_warning("GameSession: %s (no level.valley scene); showing the title" % VALLEY_MISSING)
					mode = Mode.TITLE
		"world":
			if bool(o.get("continue", false)):
				var r := _begin_continue()
				if not r.ok:
					push_warning("GameSession: --continue failed (%s); showing the title" % r.message)
					mode = Mode.TITLE
			elif world_available():
				_begin_new_world(_cli_start)
			else:
				push_warning("GameSession: %s (no level.world scene); showing the title" % WORLD_MISSING)
				mode = Mode.TITLE
		_:
			mode = Mode.TITLE


# --------------------------------------------------------------------------- modes and levels

## The scene main.gd loads for the current mode ("" for the title, or when the level does not
## exist yet): the --level / test scene, the sandbox, or the campaign level's scene.
func level_scene_path() -> String:
	if level_override != "":
		return level_override
	match mode:
		Mode.SANDBOX:
			return SANDBOX_SCENE
		Mode.VALLEY:
			return scene_for_level(level_id if level_id != "" else VALLEY_LEVEL_ID)
	return ""


func is_valley() -> bool:
	return mode == Mode.VALLEY


## The campaign (the Valley and the world): an alias of is_valley() (P20, decision 11).
func is_campaign() -> bool:
	return is_valley()


func checkpoints_enabled() -> bool:
	return is_campaign() or test_checkpoints


## True when New Game can start: the Valley scene (or the --level scene) exists.
func valley_available() -> bool:
	var path := level_override if level_override != "" else scene_for_level(VALLEY_LEVEL_ID)
	return path != "" and ResourceLoader.exists(path)


## True when the world can start (--mode=world, the title's skip-prologue choice): the
## level.world record's scene exists (or the --level scene stands in for it).
func world_available() -> bool:
	var path := level_override if level_override != "" else scene_for_level(WORLD_LEVEL_ID)
	return path != "" and ResourceLoader.exists(path)


## The scene of a save's "level": a res:// scene path itself, or a level record's scene.
func scene_for_level(p_level_id: String) -> String:
	if p_level_id.begins_with("res://"):
		return p_level_id
	var rec := GameData.get_record(p_level_id)
	return str(rec.get("scene", "")) if str(rec.get("type", "")) == "level" else ""


## True when a save document's level can be loaded by this build: its scene exists, or it names a
## campaign level record this build lacks while the Valley exists (Continue then falls back to the
## Valley with a message, P20).
func save_level_available(doc: Dictionary) -> bool:
	var lv := str(doc.get("level", VALLEY_LEVEL_ID))
	var scene := scene_for_level(lv)
	if scene != "" and ResourceLoader.exists(scene):
		return true
	return _falls_back_to_valley(lv)


## A level record id (not a scene path) whose scene this build lacks, with the Valley present.
func _falls_back_to_valley(p_level_id: String) -> bool:
	if p_level_id.begins_with("res://") or p_level_id == VALLEY_LEVEL_ID:
		return false
	var valley := scene_for_level(VALLEY_LEVEL_ID)
	return valley != "" and ResourceLoader.exists(valley)


func has_checkpoint() -> bool:
	return not checkpoint_doc.is_empty()


## The campaign level being played (level_id); "" outside the campaign (P20).
func current_level_id() -> String:
	return level_id if is_campaign() else ""


## The level id written into save documents: the campaign's level_id, else (a test level in the
## sandbox) the --level scene or the loaded level's scene path.
func save_level_id() -> String:
	if is_campaign():
		if level_id != "":
			return level_id
		return level_override if level_override != "" else VALLEY_LEVEL_ID
	if level_override != "":
		return level_override
	var level := _level()
	if level != null and level.scene_file_path != "":
		return level.scene_file_path
	return SANDBOX_SCENE


## Title and pause screens emit Events.mode_change_requested(mode, options); this is what it
## does. mode: "title" | "sandbox" | "valley" (options: {"new_game": true} or
## {"continue": true}; neither = continue when a save loads, else a new game) | "world" (P20: a
## New Game from world_start in level.world - the title's "Skip to the Old Kingdom").
## Returns {"ok", "message"}.
func change_mode(mode_name: String, options: Dictionary = {}) -> Dictionary:
	match mode_name:
		"title":
			go_to_title()
			return {"ok": true, "message": ""}
		"sandbox":
			start_sandbox()
			return {"ok": true, "message": ""}
		"valley":
			# Continue needs the save's level (a --level test scene can stand in for the Valley);
			# New Game needs the Valley (or the --level scene).
			if bool(options.get("continue", false)):
				return continue_valley()
			if not bool(options.get("new_game", false)):
				var r := continue_valley()
				if r.ok:
					return r
			if not valley_available():
				return {"ok": false, "message": VALLEY_MISSING}
			start_new_valley()
			return {"ok": true, "message": ""}
		"world":
			if not world_available():
				return {"ok": false, "message": WORLD_MISSING}
			start_new_world(str(options.get("start", "")))
			return {"ok": true, "message": ""}
	return {"ok": false, "message": "Unknown mode '%s'" % mode_name}


## New Game: a clean world, the progression record's new character, then the Valley loads. The
## first on_level_ready keeps the player at the scene's Player node, sets respawn_id to the
## level's start checkpoint and takes the first checkpoint (written when persist is true).
func start_new_valley() -> void:
	if not valley_available():
		push_warning("GameSession: %s" % VALLEY_MISSING)
		return
	_begin_new_valley()
	_reload_scene("new_game")


## New Game in the world (P20, plan M6-M9 §2.6): the campaign starts in level.world with
## progression.default's world_start character, inventory and flags (the Valley's worst
## guaranteed outcome), at `start_checkpoint` or the world's start checkpoint.
func start_new_world(start_checkpoint := "") -> void:
	if not world_available():
		push_warning("GameSession: %s" % WORLD_MISSING)
		return
	_begin_new_world(start_checkpoint)
	_reload_scene("new_game")


## --mode=world --new-game [--start=<checkpoint>] for tests (P20): the session is set up exactly as
## the command line would; the reload is only logged in tests, which build their level and call
## on_level_ready themselves. The world level does not need to exist (tests stub its record).
func start_world_for_tests(start_checkpoint := "") -> void:
	_begin_new_world(start_checkpoint)
	_reload_scene("new_game")


## Continue: reads the save slot and loads it exactly (no death floor). {"ok", "message"}.
func continue_valley() -> Dictionary:
	var r := _begin_continue()
	if r.ok:
		_reload_scene("continue")
	return r


func start_sandbox() -> void:
	mode = Mode.SANDBOX
	_clear_session()
	level_override = _cli_level_override
	_reload_scene("sandbox")


## Back to the title. A level a Continue loaded from its save (a test level's scene path) is
## forgotten here (P16, M3 review): the Sandbox and New Game started from the title load their own
## levels again (or the command line's --level).
func go_to_title() -> void:
	_commit_pending_completion()
	mode = Mode.TITLE
	_clear_session()
	level_override = _cli_level_override
	_reload_scene("title")


## The slice's completion checkpoint (or a boss's end, M8 gate), if it still waits (something other
## than an aware enemy held it back), is committed before a quit to the title clears the session
## (P17a, M4 review: Quit to title on the end screen lost it). A dead giant is never saved, nor (M8
## release, R1) a world in the middle of a boss fight or battle: the quit leaves the fight, and the save
## keeps the world from before it.
func _commit_pending_completion() -> void:
	if _pending.is_empty() or not bool(_pending.get("completion", false)) or not checkpoints_enabled():
		return
	if _player_dead() or not engaged_fights().is_empty():
		return
	_commit_checkpoint(str(_pending.reason), str(_pending.respawn))


## A sandbox reset (death restart, F5, the pause menu, the autopilot): forget every world change
## and checkpoint of this level and reload it.
func restart_sandbox(reason: String) -> void:
	_clear_session()
	_reload_scene(reason)


func _begin_new_valley(start_checkpoint := "") -> void:
	mode = Mode.VALLEY
	WorldState.clear()
	Sim.clear_pending()
	character = CharacterState.new_game(GameData.get_record(PROGRESSION_ID), GameData.get_record(PLAYER_ID))
	level_id = level_override if level_override != "" else VALLEY_LEVEL_ID
	_reset_campaign_state()
	_start_override = start_checkpoint


## The world's New Game: world_start's character, inventory and flags (a bulk load: no events).
func _begin_new_world(start_checkpoint := "") -> void:
	mode = Mode.VALLEY
	WorldState.clear()
	Sim.clear_pending()
	var prog := GameData.get_record(PROGRESSION_ID)
	character = CharacterState.world_start(prog, GameData.get_record(PLAYER_ID))
	var ws: Dictionary = prog.get("world_start", {}) if typeof(prog.get("world_start")) == TYPE_DICTIONARY else {}
	WorldState.from_save_dict({"schema_version": WorldState.SCHEMA_VERSION, "deltas": {},
		"inventory": CharacterState.inventory_of(ws.get("inventory", [])),
		"flags": (ws.get("flags", {}) as Dictionary).duplicate(true) if typeof(ws.get("flags")) == TYPE_DICTIONARY else {}})
	level_id = level_override if level_override != "" else WORLD_LEVEL_ID
	_reset_campaign_state()
	progress.prologue_complete = true
	_start_override = start_checkpoint


## The campaign's per-game state before a New Game's first load.
func _reset_campaign_state() -> void:
	checkpoint_doc = {}
	respawn_id = ""
	stats = _zero_stats()
	progress = default_progress()
	_pending = {}
	_reload_floor = {}
	last_load_message = ""
	pending_restore = true
	_load_reason = "new_game"
	_start_override = ""


func _begin_continue() -> Dictionary:
	if not persist:
		return {"ok": false, "message": "Continue is off: saving is off for this run."}
	var read := SaveSlots.read()
	if not read.ok:
		return {"ok": false, "message": str(read.message) if str(read.message) != "" else "No saved game yet."}
	var doc: Dictionary = read.data
	var saved_level := str(doc.get("level", VALLEY_LEVEL_ID))
	if not save_level_available(doc):
		return {"ok": false, "message": "The saved level is not in this build (%s)." % saved_level}
	var world: Dictionary = doc.get("world", {})
	if not WorldState.from_save_dict(world):
		return {"ok": false, "message": "The save's world state could not be loaded."}
	var message := str(read.message)
	var target := saved_level
	var respawn := str((doc.get("checkpoint", {}) as Dictionary).get("respawn", ""))
	var scene := scene_for_level(saved_level)
	if scene == "" or not ResourceLoader.exists(scene):
		# A campaign level this build does not have (a newer build's world): the Valley instead.
		target = VALLEY_LEVEL_ID
		respawn = _valley_return_checkpoint()
		message = _join_message(message, "%s (%s): you continue in the Valley." % [WORLD_MISSING, saved_level])
		doc = doc.duplicate(true)
		doc["level"] = VALLEY_LEVEL_ID
		(doc["checkpoint"] as Dictionary)["respawn"] = respawn
	level_override = target if target.begins_with("res://") else ""
	level_id = target
	mode = Mode.VALLEY
	character = (doc.character as Dictionary).duplicate(true)
	checkpoint_doc = doc
	respawn_id = respawn
	stats = _stats_from(doc.get("stats", {}))
	stats.checkpoint_loads = int(stats.checkpoint_loads) + 1
	progress = progress_from(doc.get("progress", {}))
	_pending = {}
	_reload_floor = {}
	_start_override = ""
	last_load_message = message
	pending_restore = true
	_load_reason = "continue"
	Sim.clear_pending()
	return {"ok": true, "message": message}


## Where a fall-back to the Valley puts the player: its return checkpoint when the Valley's index
## has it (P26), else the Valley's start checkpoint.
func _valley_return_checkpoint() -> String:
	var idx := WorldIndex.for_level(VALLEY_LEVEL_ID)
	if idx != null and idx.has_checkpoint(VALLEY_RETURN_CHECKPOINT):
		return VALLEY_RETURN_CHECKPOINT
	return str(GameData.get_record(VALLEY_LEVEL_ID).get("start_checkpoint", ""))


func _clear_session() -> void:
	WorldState.clear()
	Sim.clear_pending()
	character = {}
	checkpoint_doc = {}
	respawn_id = ""
	pending_restore = false
	stats = _zero_stats()
	progress = {}
	level_id = ""
	_pending = {}
	_load_reason = ""
	_reload_floor = {}
	_start_override = ""
	_visit_activated.clear()


func _reload_scene(reason: String) -> void:
	scene_reloads.append(reason)
	if scene_reloads.size() > MAX_RELOAD_LOG:
		scene_reloads.remove_at(0)
	if not allow_scene_reload or _reload_queued or not is_inside_tree():
		return
	_reload_queued = true
	ScreenStack.close_all_static()
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")
	call_deferred("_clear_reload_queued")


func _clear_reload_queued() -> void:
	_reload_queued = false


# --------------------------------------------------------------------------- level start

## main.gd calls this after it added the level, the HUD and the screen stack. A level load starts
## a new level visit (activated_this_visit is cleared). With a pending restore it moves the player
## to the respawn point (respawn_checkpoint(): the node, else the level's world index), applies
## `character`, then the death floor after a death. A New Game keeps the scene's Player position
## (or goes to the --start checkpoint) and takes the first checkpoint. A checkpointed level started
## without a session document (a test level in the sandbox) takes a first in-memory checkpoint.
## level_entered follows once the level and the samples are ready (every load with a player: the
## sandbox's and a reset's with reason "debug").
func on_level_ready(level: Node, player: GiantPlayer) -> void:
	_level_ref = weakref(level) if level != null else null
	_player_ref = weakref(player) if player != null else null
	_visit_activated.clear()
	if player == null:
		return
	if pending_restore:
		pending_restore = false
		var reason := _load_reason
		_load_reason = ""
		_restoring = true
		if reason == "new_game":
			if _start_override != "":
				var start := respawn_transform(_start_override)
				if start.origin.is_finite():
					place_player(player, start)
				respawn_id = _start_override
				_start_override = ""
		else:
			var allowed := respawn_checkpoint()
			if allowed != respawn_id and allowed != "":
				_note_respawn_moved(respawn_id, allowed)
				respawn_id = allowed
			var t := respawn_transform(respawn_id)
			if t.origin.is_finite():
				place_player(player, t)
		player.apply_character_state(character)
		_apply_level_exempt(player, character)
		if not _reload_floor.is_empty():
			apply_reload_floor(player, _reload_floor)
			_reload_floor = {}
		character = CharacterState.normalize(player.capture_character_state())
		_restoring = false
		_note_level_visit()
		_restore_tracked_quest()
		if reason == "new_game":
			if respawn_id == "":
				respawn_id = _start_checkpoint(level)
			_commit_checkpoint("new_game", "")
		else:
			Events.checkpoint_loaded.emit(Sim.tick, respawn_id, reason if reason != "" else "load")
		_request_level_entered(level, reason)
	elif checkpoints_enabled() and checkpoint_doc.is_empty():
		if respawn_id == "":
			respawn_id = _start_checkpoint(level)
		_commit_checkpoint("level_start", "")
		_request_level_entered(level, "debug")
	else:
		# Any other load (the sandbox, a reset, a test level's later loads) is entered too.
		_request_level_entered(level, "debug")


## The CheckpointMarker (or Waystone, or shrine SpawnPoint) with this id, or null.
func find_checkpoint(checkpoint_id: String) -> CheckpointMarker:
	if checkpoint_id == "" or not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("checkpoints"):
		var m := n as CheckpointMarker
		if m != null and m.is_inside_tree() and m.checkpoint_id == checkpoint_id:
			return m
	return null


## Where a respawn at `checkpoint_id` puts the player (P20): the checkpoint node's
## spawn_transform() when it is loaded, else the current level's world index entry (position and
## yaw). A Transform3D with an INF origin when neither knows it (the player then stays where the
## scene put it).
func respawn_transform(checkpoint_id: String) -> Transform3D:
	var marker := find_checkpoint(checkpoint_id)
	if marker != null:
		return marker.spawn_transform()
	var idx := WorldIndex.for_level(save_level_id())
	if idx != null:
		return idx.spawn_transform(checkpoint_id)
	return Transform3D(Basis(), Vector3.INF)


## The checkpoint a load respawns at (P20): the saved respawn unless a blocker refuses it, else
## the nearest visited (flag visited.<id>) unblocked checkpoint of the level's index, else its
## start checkpoint when unblocked, else the nearest unblocked one; the saved respawn when every
## checkpoint is refused (or the level has no index).
func respawn_checkpoint() -> String:
	return _respawn_for(respawn_id, save_level_id(), current_stage())


## respawn_checkpoint()'s rule for a saved respawn `saved` of level `lv` and a giant of `stage`.
func _respawn_for(saved: String, lv: String, stage: int) -> String:
	if saved == "" or respawn_blocker(saved, lv, stage) == "":
		return saved
	var idx := WorldIndex.for_level(lv)
	if idx == null:
		return saved
	var origin := idx.position_of(saved)
	var best_visited := ""
	var best_visited_d := INF
	var best_any := ""
	var best_any_d := INF
	for id in idx.checkpoint_ids():
		if id == saved or respawn_blocker(id, lv, stage) != "":
			continue
		var p := idx.position_of(id)
		var d := p.distance_to(origin) if origin.is_finite() else 0.0
		if QuestConditions.truthy(WorldState.get_flag(VISITED_PREFIX + id)) and d < best_visited_d:
			best_visited = id
			best_visited_d = d
		if d < best_any_d:
			best_any = id
			best_any_d = d
	if best_visited != "":
		return best_visited
	var rec := GameData.get_record(lv)
	var start := str(rec.get("start_checkpoint", "")) if str(rec.get("type", "")) == "level" else ""
	if start != "" and start != saved and idx.has_checkpoint(start) and respawn_blocker(start, lv, stage) == "":
		return start
	return best_any if best_any != "" else saved


## M8 release (R2): the checkpoint a Continue of the save document `doc` wakes the giant at, before the
## save is loaded (the title's saved-game line names it: TitleScreen.describe_save). respawn_checkpoint()'s
## rule judged for that save - its level, saved respawn and the character's stage, its world (swapped into
## WorldState for the call and back: bulk loads emit nothing) - with the blockers its level registers once it
## loads, which are not registered at the title: FactionState's guards (FactionState.respawn_refusal) and a
## world event's run the save holds in progress (WanderDirector.saved_run_refusal). The 0.7.0-m7 save at
## the Brannock waystone with Brannock hostile read "at the Brannock waystone" while Continue woke the giant at
## the Kingsgate shelf waystone. The saved respawn when the document has no world.
func save_respawn(doc: Dictionary) -> String:
	var cp: Variant = doc.get("checkpoint")
	var saved := str((cp as Dictionary).get("respawn", "")) if typeof(cp) == TYPE_DICTIONARY else ""
	var doc_world: Variant = doc.get("world")
	if saved == "" or typeof(doc_world) != TYPE_DICTIONARY:
		return saved
	var lv := str(doc.get("level", VALLEY_LEVEL_ID))
	var ch: Variant = doc.get("character")
	var stage := maxi(1, int((ch as Dictionary).get("growth_stage", 1))) if typeof(ch) == TYPE_DICTIONARY else 1
	var live := WorldState.to_save_dict()
	if not WorldState.from_save_dict(doc_world as Dictionary):
		return saved
	var level_blockers: Array[Callable] = [
		func(id: String) -> String: return FactionState.respawn_refusal(id),
		func(id: String) -> String: return WanderDirector.saved_run_refusal(id),
	]
	_respawn_blockers.append_array(level_blockers)
	var out := _respawn_for(saved, lv, stage)
	for b in level_blockers:
		_respawn_blockers.erase(b)
	WorldState.from_save_dict(live)
	return out


## Why a respawn at `checkpoint_id` is refused ("" = it is fine): its index max_stage below the
## character's stage (built in; `stage` when given, else current_stage()), else the first registered
## blocker's reason. The checkpoint is the save's level's, or `p_level_id`'s when given (a fast travel's
## destination: the registered blockers judge that level meanwhile - respawn_blocker_level()).
func respawn_blocker(checkpoint_id: String, p_level_id := "", stage := 0) -> String:
	var lv := p_level_id if p_level_id != "" else save_level_id()
	var idx := WorldIndex.for_level(lv)
	var st := stage if stage > 0 else current_stage()
	if idx != null and idx.has_checkpoint(checkpoint_id) and idx.max_stage_of(checkpoint_id) < st:
		return NARROW_PATHS
	var previous := _blocker_level
	_blocker_level = lv
	var why := ""
	for i in range(_respawn_blockers.size() - 1, -1, -1):
		var b: Callable = _respawn_blockers[i]
		if not b.is_valid():
			_respawn_blockers.remove_at(i)
			continue
		why = str(b.call(checkpoint_id))
		if why != "":
			break
	_blocker_level = previous
	return why


## The level whose checkpoint a registered respawn blocker is asked about: the save's level, or the
## level respawn_blocker() was given (a fast travel's destination). Blockers read it instead of
## save_level_id() (FactionState.respawn_refusal).
func respawn_blocker_level() -> String:
	return _blocker_level if _blocker_level != "" else save_level_id()


## M7 gate: a load whose saved respawn a blocker refused moves the giant to `to_id` (on_level_ready)
## and says so - why and where it wakes - on the HUD and in last_load_message, never silently.
func _note_respawn_moved(from_id: String, to_id: String) -> void:
	var why := respawn_blocker(from_id)
	var where := checkpoint_display_name(to_id)
	if where == "":
		where = "another resting place"
	else:
		where = TextUtil.with_the(where)   # M9 gate (lane review): "the Broken Stair", not "The Broken Stair"
	var line := "%s You wake at %s." % [why if why != "" else "You cannot wake there now.", where]
	last_load_message = _join_message(last_load_message, line)
	Events.hud_message.emit(line, "warn")


## Adds a respawn blocker: Callable(checkpoint_id: String) -> String (a reason, "" = fine). P29
## refuses checkpoints with hostile guards within 120 m, P37 those near an active world event.
## Blockers whose object is freed are dropped.
func register_respawn_blocker(blocker: Callable) -> void:
	if blocker.is_valid() and not _respawn_blockers.has(blocker):
		_respawn_blockers.append(blocker)


func unregister_respawn_blocker(blocker: Callable) -> void:
	_respawn_blockers.erase(blocker)


## The growth stage that arrival limits compare: the live player's, else the character's.
func current_stage() -> int:
	var p := player()
	if p != null:
		return p.current_growth_stage()
	return maxi(1, int(character.get("growth_stage", 1)))


## The level record of the campaign level ({} for a test level's scene path or outside it).
func level_record() -> Dictionary:
	var rec := GameData.get_record(save_level_id())
	return rec if str(rec.get("type", "")) == "level" else {}


# --------------------------------------------------------------------------- visits

## True when a shrine or waystone with this checkpoint id was activated during this level visit
## (P20): a node made again (a streamed chunk reloading) gives no second rest or checkpoint.
func activated_this_visit(checkpoint_id: String) -> bool:
	return checkpoint_id != "" and _visit_activated.has(checkpoint_id)


func mark_activated(checkpoint_id: String) -> void:
	if checkpoint_id != "":
		_visit_activated[checkpoint_id] = true


## The campaign's bookkeeping when a level loads: levels_visited, world_entered (and the flag
## progress.world_entered) when the level is the world.
func _note_level_visit() -> void:
	if not is_campaign() or level_id == "":
		return
	if progress.is_empty():
		progress = default_progress()
	var visited: Array = progress.levels_visited
	if not visited.has(level_id):
		visited.append(level_id)
	if level_id == WORLD_LEVEL_ID:
		progress.world_entered = true
		WorldState.try_set_flag("progress.world_entered", true)


## Asks for level_entered: at once when the level (its is_ready(), when it has one) and the
## samples (Audio.is_ready(), when the autoload has it) are ready, else on a later frame.
func _request_level_entered(level: Node, reason: String) -> void:
	var r := reason
	if r == "menu" or r == "" or r == "load":
		r = "continue"
	if not ENTER_REASONS.has(r):
		r = "debug"
	_entering = {"level": weakref(level) if level != null else null, "level_id": save_level_id(),
		"reason": r, "frames": 0}
	if _entry_ready():
		_emit_level_entered()
	elif is_inside_tree() and not get_tree().process_frame.is_connected(_poll_level_entered):
		get_tree().process_frame.connect(_poll_level_entered)


func _entry_ready() -> bool:
	var ref: Variant = _entering.get("level")
	var level: Object = (ref as WeakRef).get_ref() if ref is WeakRef else null
	if level != null and is_instance_valid(level) and level.has_method("is_ready") and not bool(level.call("is_ready")):
		return false
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("is_ready") and not bool(audio.call("is_ready")):
		return false
	return true


func _poll_level_entered() -> void:
	if _entering.is_empty():
		_stop_polling_entered()
		return
	_entering.frames = int(_entering.frames) + 1
	var ref: Variant = _entering.get("level")
	var level: Object = (ref as WeakRef).get_ref() if ref is WeakRef else null
	if level == null or not is_instance_valid(level):
		_entering = {}
		_stop_polling_entered()
		return
	if _entry_ready() or int(_entering.frames) >= ENTER_WAIT_FRAMES:
		if int(_entering.frames) >= ENTER_WAIT_FRAMES:
			push_warning("GameSession: level_entered sent after %d frames without the level or the samples ready" % ENTER_WAIT_FRAMES)
		_emit_level_entered()


func _emit_level_entered() -> void:
	_stop_polling_entered()
	var e := _entering
	_entering = {}
	if e.is_empty():
		return
	entered_log.append({"tick": Sim.tick, "level": str(e.level_id), "reason": str(e.reason)})
	if entered_log.size() > MAX_RELOAD_LOG:
		entered_log.remove_at(0)
	Events.level_entered.emit(Sim.tick, str(e.level_id), str(e.reason))


func _stop_polling_entered() -> void:
	if is_inside_tree() and get_tree().process_frame.is_connected(_poll_level_entered):
		get_tree().process_frame.disconnect(_poll_level_entered)


## True while a level_entered waits for its level or the samples.
func level_entered_pending() -> bool:
	return not _entering.is_empty()


# --------------------------------------------------------------------------- travel

## Leaves the current campaign level for `p_level_id`, arriving at `checkpoint_id` (P20, plan
## M6-M9 §2.6). reason: exit (a LevelExit) | fast_travel (the map, P27) | debug | bot. Refused
## ({"ok": false, "message"}) outside the campaign; for a level this build does not have; with
## the checkpoint blockers (an exit ignores aware enemies, fast travel ignores the open screen it
## comes from); when the destination's index does not know the checkpoint or its max_stage is
## below the giant's stage; and for fast travel when the checkpoint was not visited, is not a fast
## travel point, or its requires_flags do not hold. Otherwise commits a checkpoint document whose
## level is the destination and whose respawn is the checkpoint (with its index position), emits
## level_leaving and reloads main.tscn; the next on_level_ready puts the player there with the
## character, flags and world deltas intact. {"ok": true, "message": ""}.
func travel_to(p_level_id: String, checkpoint_id: String, reason: String) -> Dictionary:
	if not is_campaign():
		return {"ok": false, "message": "There is nowhere to travel from here."}
	var why := travel_refusal(p_level_id, checkpoint_id, reason)
	if why != "":
		return {"ok": false, "message": why}
	var from := level_id
	level_id = p_level_id
	level_override = p_level_id if p_level_id.begins_with("res://") else ""
	_pending = {}
	_commit_checkpoint("travel" if reason == "exit" else reason, checkpoint_id)
	Events.level_leaving.emit(Sim.tick, from, p_level_id, reason)
	_load_reason = "fast_travel" if reason == "fast_travel" else "travel"
	_reload_floor = {}
	pending_restore = true
	stats.checkpoint_loads = int(stats.checkpoint_loads) + 1
	Sim.clear_pending()
	_reload_scene(_load_reason)
	return {"ok": true, "message": ""}


## Why travel_to would refuse now ("" = it would go). See travel_to.
func travel_refusal(p_level_id: String, checkpoint_id: String, reason: String) -> String:
	if not TRAVEL_REASONS.has(reason):
		return "Unknown travel reason '%s'." % reason
	var scene := scene_for_level(p_level_id)
	if scene == "" or not ResourceLoader.exists(scene):
		return "That land is not in this build."
	var blockers := travel_blockers(reason)
	if not blockers.is_empty():
		return blocker_text(blockers)
	var idx := WorldIndex.for_level(p_level_id)
	if idx != null and checkpoint_id != "":
		if not idx.has_checkpoint(checkpoint_id):
			return UNKNOWN_PLACE
		if idx.max_stage_of(checkpoint_id) < current_stage():
			return NARROW_PATHS
	if reason == "fast_travel":
		if not QuestConditions.truthy(WorldState.get_flag(VISITED_PREFIX + checkpoint_id)):
			return NOT_VISITED
		var entry := idx.checkpoint(checkpoint_id) if idx != null else {}
		if not entry.is_empty() and not bool(entry.get("fast_travel", true)):
			return NOT_OPEN
		for f: Variant in entry.get("requires_flags", PackedStringArray()):
			if not QuestConditions.truthy(WorldState.get_flag(str(f))):
				return NOT_OPEN
		# M7 gate: arriving is a respawn there, so a stone its respawn blockers refuse (hostile
		# guards near it, P29) is refused here with their reason - the map shows it and keeps Travel
		# off - instead of a reload that silently woke the giant at another stone.
		var held := respawn_blocker(checkpoint_id, p_level_id)
		if held != "":
			return held
	return ""


## The checkpoint blockers that hold a travel back: all of them, but an exit never waits for
## aware enemies and fast travel never for the screen it is chosen from.
func travel_blockers(reason: String) -> PackedStringArray:
	var out := PackedStringArray()
	for b in checkpoint_blockers(reason == "exit"):
		if reason == "fast_travel" and b == "screen":
			continue
		out.append(b)
	return out


## A player-facing line for checkpoint_blockers() codes (the first one decides).
static func blocker_text(blockers: PackedStringArray) -> String:
	if blockers.is_empty():
		return ""
	var b := blockers[0]
	if b.begins_with("aware:"):
		return "Not while enemies are close."
	if b.begins_with(FIGHT_BLOCKER_PREFIX):
		return FIGHT_BLOCKED
	match b:
		"dead":
			return "The dead cannot travel."
		"grabbed":
			return "Not while you are held."
		"executing":
			return "Not in the middle of a blow."
		"holding":
			return "Put down what you are holding first."
		"screen":
			return "Close the menu first."
		"no_player":
			return "There is no giant to travel."
	return "You cannot travel now."


func _on_travel_requested(p_level_id: String, checkpoint_id: String, reason: String) -> void:
	last_travel_result = travel_to(p_level_id, checkpoint_id, reason)
	if not bool(last_travel_result.ok):
		Events.hud_message.emit(str(last_travel_result.message), "warn")


# --------------------------------------------------------------------------- level start helpers

## Puts the player at `t` (position and yaw) as if it had spawned there.
static func place_player(player: GiantPlayer, t: Transform3D) -> void:
	player.global_transform = t
	player.velocity = Vector3.ZERO
	player.move_velocity = Vector3.ZERO
	player.knockback_velocity = Vector3.ZERO
	player.facing_yaw = t.basis.get_euler().y
	player.spawn_transform = t
	if player.camera_rig != null:
		player.camera_rig.yaw = player.facing_yaw


## Raises the player's pools to at least floor x maximum (health, stamina, essence), sets fury
## to 0 and clears its statuses (a death reload).
static func apply_reload_floor(player: GiantPlayer, floor_fracs: Dictionary) -> void:
	var combatant := player.entity.combatant
	var pools := combatant.pools
	pools.restore({
		"health": maxf(pools.health, pools.health_max * float(floor_fracs.get("health", 0.0))),
		"stamina": maxf(pools.stamina, pools.stamina_max * float(floor_fracs.get("stamina", 0.0))),
		"essence": maxf(pools.essence, pools.essence_max * float(floor_fracs.get("essence", 0.0))),
		"fury": 0.0})
	combatant.statuses.clear()


## progression.default.death_reload_floor (health 0.6, stamina 1.0, essence 0.5 by default).
func death_reload_floor() -> Dictionary:
	var rec := GameData.get_record(PROGRESSION_ID)
	var floor_fracs: Dictionary = DEFAULT_DEATH_FLOOR.duplicate()
	if typeof(rec.get("death_reload_floor")) == TYPE_DICTIONARY:
		floor_fracs.merge(rec.death_reload_floor, true)
	return floor_fracs


## Until a progression component (P12) owns it, the session puts the character's level_exempt
## ids into the controller (GiantPlayer applies `level` itself).
static func _apply_level_exempt(player: GiantPlayer, state: Dictionary) -> void:
	if player.progression != null or not ("level_exempt" in player.controller):
		return
	if typeof(state.get("level_exempt")) != TYPE_ARRAY:
		return
	var exempt := {}
	for id: Variant in state.level_exempt:
		exempt[str(id)] = true
	player.controller.set("level_exempt", exempt)


## The level's start checkpoint: its root's start_checkpoint property, else the start_checkpoint
## of its level record (by the root's level_id, else by scene path).
func _start_checkpoint(level: Node) -> String:
	if level != null and "start_checkpoint" in level:
		return str(level.get("start_checkpoint"))
	if level != null and "level_id" in level:
		var by_id := GameData.get_record(str(level.get("level_id")))
		if str(by_id.get("type", "")) == "level":
			return str(by_id.get("start_checkpoint", ""))
	var path := level_scene_path()
	for rec: Dictionary in GameData.records_of_type("level"):
		if str(rec.get("scene", "")) == path:
			return str(rec.get("start_checkpoint", ""))
	return ""


# --------------------------------------------------------------------------- checkpoints

## Queues a checkpoint, taken in POST_RESOLVE as soon as checkpoint_blockers() is empty. One
## request is pending at a time: a later one replaces the reason and, when it names a respawn,
## the respawn. Ignored where checkpoints are off (the sandbox).
## completion (P17a, M4 review): the slice's completion (Quests, when quest.main ends). It does
## not wait for aware enemies - the crown can be taken with the Barrow's wardens still about, and
## the end screen that opens next offers Quit to title - and a quit to the title commits it if it
## is still pending (go_to_title), so the completed slice is never lost. It stays set on the
## pending request until that is taken. M8 gate (fix-up 1): a boss's end (boss_defeated, a
## drive-out) is a completion request too.
func request_checkpoint(reason: String, respawn: String = "", completion := false) -> void:
	if not checkpoints_enabled():
		return
	if _pending.is_empty():
		_pending = {"reason": reason, "respawn": respawn, "tick": Sim.tick, "completion": completion}
		return
	_pending.reason = reason
	if respawn != "":
		_pending.respawn = respawn
	if completion:
		_pending["completion"] = true


## Takes a checkpoint now when allowed, otherwise queues it (deferred). respawn "" keeps the
## current respawn point; completion: see request_checkpoint. Returns {"ok", "message",
## "deferred"}.
func take_checkpoint(reason: String, respawn: String = "", completion := false) -> Dictionary:
	if not checkpoints_enabled():
		return {"ok": false, "message": "no checkpoints here", "deferred": false}
	var blockers := checkpoint_blockers(completion)
	if not blockers.is_empty():
		request_checkpoint(reason, respawn, completion)
		return {"ok": false, "message": "deferred: " + ", ".join(blockers), "deferred": true}
	return _commit_checkpoint(reason, respawn)


## Why a checkpoint must wait now ([] = it may be taken): dead, grabbed, executing, holding,
## screen, fight:<boss id> (M8 release, R1: a boss fight or battle engaged - engaged_fights()),
## aware:<enemy id> (an aware enemy within 40 m), no_player. ignore_aware: leave the aware enemies out
## (the slice's completion checkpoint, a boss's end, the main thread's stages, an exit); an engaged fight
## holds those too.
func checkpoint_blockers(ignore_aware := false) -> PackedStringArray:
	var out := PackedStringArray()
	var p := player()
	if p == null or p.controller == null:
		out.append("no_player")
		return out
	match p.controller.state:
		CombatController.State.DEAD:
			out.append("dead")
		CombatController.State.GRABBED:
			out.append("grabbed")
		CombatController.State.EXECUTING:
			out.append("executing")
	if p.controller.holding_id != "":
		out.append("holding")
	if _modal_screen_open():
		out.append("screen")
	for boss_id in engaged_fights():
		out.append(FIGHT_BLOCKER_PREFIX + boss_id)
	if ignore_aware:
		return out
	for n in get_tree().get_nodes_in_group("enemies"):
		var enemy := n as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		var e: Variant = enemy.get("entity")
		if e is CombatEntity and not (e as CombatEntity).is_alive():
			continue
		var brain: Variant = enemy.get("brain")
		if brain == null or not (brain is Object) or not ("aware" in brain) or not bool(brain.get("aware")):
			continue
		if enemy.global_position.distance_to(p.global_position) <= AWARE_BLOCK_RADIUS_M:
			out.append("aware:%s" % str(enemy.get("entity_id")))
	return out


## M8 release (R1): the boss ids of the boss fights and battles engaged now - every BossArena (BattleBoss
## among them: group boss_arenas) whose is_engaged() holds. While one is, no checkpoint is committed
## (checkpoint_blockers: fight:<boss id>): a world saved mid-fight held the fight half fought (the Iron
## Regiment's Wall cleared, the battle not won), and its next engagement after a load could not be won.
func engaged_fights() -> PackedStringArray:
	var out := PackedStringArray()
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if is_instance_valid(n) and n.is_inside_tree() and n.has_method("is_engaged") and bool(n.call("is_engaged")):
			out.append(str(n.get("boss_id")))
	return out


## The document a checkpoint stores (and writes): the character (refreshed from the player when
## there is one), the world, the level and the respawn point (with its position and yaw, P20),
## the reason, the campaign's progress and the session stats.
func snapshot_document(reason: String) -> Dictionary:
	var p := player()
	if p != null and not _restoring:
		character = CharacterState.normalize(p.capture_character_state())
	var lv := save_level_id()
	var cp := {"respawn": respawn_id, "reason": reason}
	var where := _checkpoint_place(lv, respawn_id)
	if not where.is_empty():
		cp["position"] = [where.position.x, where.position.y, where.position.z]
		cp["yaw"] = float(where.yaw)
	return {
		"schema_version": SaveSlots.SCHEMA_VERSION,
		"build_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"slot": SaveSlots.SLOT,
		"level": lv,
		"checkpoint": cp,
		"character": character.duplicate(true),
		"world": WorldState.to_save_dict(),
		"progress": _progress_snapshot(),
		"stats": stats.duplicate(true),
	}


## {"position": Vector3, "yaw": float} of a checkpoint of `lv`: its index entry, else its node when
## that level is the loaded one; {} when neither knows it.
func _checkpoint_place(lv: String, checkpoint_id: String) -> Dictionary:
	if checkpoint_id == "":
		return {}
	var idx := WorldIndex.for_level(lv)
	if idx != null and idx.has_checkpoint(checkpoint_id):
		var e := idx.checkpoint(checkpoint_id)
		return {"position": e.position, "yaw": float(e.get("yaw", 0.0))}
	var marker := find_checkpoint(checkpoint_id)
	if marker != null and _is_loaded_level(lv):
		var t := marker.spawn_transform()
		return {"position": t.origin, "yaw": t.basis.get_euler().y}
	return {}


## True when `lv` is the level on screen: its root's level_id or scene path (a travel's destination
## is not, so a checkpoint node of the level being left never gives the arrival its position).
## True when there is no level root to ask (tests that call on_level_ready without one).
func _is_loaded_level(lv: String) -> bool:
	var level := _level()
	if level == null:
		return true
	if level.scene_file_path != "" and level.scene_file_path == lv:
		return true
	if "level_id" in level and str(level.get("level_id")) != "":
		return str(level.get("level_id")) == lv
	return lv == save_level_id() and level.scene_file_path == ""


func _commit_checkpoint(reason: String, respawn: String) -> Dictionary:
	var new_respawn := respawn
	if new_respawn == "" and not _pending.is_empty():
		new_respawn = str(_pending.respawn)
	_pending = {}
	if new_respawn != "":
		respawn_id = new_respawn
	checkpoint_doc = snapshot_document(reason)
	checkpoints_taken += 1
	var result := {"ok": true, "message": "", "deferred": false}
	if _writes_enabled():
		var w := SaveSlots.write(checkpoint_doc)
		result.ok = bool(w.ok)
		result.message = str(w.message)
		if not w.ok:
			push_warning("GameSession: checkpoint not saved: %s" % w.message)
			Events.hud_message.emit("Checkpoint not saved: %s. Play continues." % w.message, "warn")
	else:
		result.message = NO_SAVING if is_campaign() else MEMORY_ONLY
	Events.checkpoint_saved.emit(Sim.tick, respawn_id, bool(result.ok), str(result.message))
	return result


## The campaign writes the slot (with persist); test levels in the sandbox never do, so they can
## never overwrite the player's save.
func _writes_enabled() -> bool:
	return persist and is_campaign()


## Reloads the last checkpoint: its world and character come back and the scene reloads; the
## next on_level_ready puts the player at its respawn point. reason "death" applies the death
## floor (decision 13); "continue", "debug" and "menu" restore it exactly - unless the player is
## dead when they are asked for (P16, M3 review: the pause menu's Load last checkpoint or F9 on
## the death screen is a death reload too, so it gets the floor). The checkpoint's level loads
## (P20: it can be another level than the one on screen only after a travel's checkpoint).
func reload_checkpoint(reason: String) -> void:
	if not checkpoints_enabled() or checkpoint_doc.is_empty():
		Events.hud_message.emit("No checkpoint to load yet", "warn")
		return
	var dead := _player_dead()
	var doc := checkpoint_doc
	if not WorldState.from_save_dict(doc.get("world", {}) as Dictionary):
		Events.hud_message.emit("The checkpoint's world state is damaged; it was not loaded", "bad")
		return
	character = (doc.get("character", {}) as Dictionary).duplicate(true)
	respawn_id = str((doc.get("checkpoint", {}) as Dictionary).get("respawn", respawn_id))
	if is_campaign() and typeof(doc.get("level")) == TYPE_STRING and str(doc.level) != "":
		level_id = str(doc.level)
	if typeof(doc.get("progress")) == TYPE_DICTIONARY:
		progress = progress_from(doc.progress)
	_reload_floor = death_reload_floor() if reason == "death" or dead else {}
	_pending = {}
	stats.checkpoint_loads = int(stats.checkpoint_loads) + 1
	pending_restore = true
	_load_reason = reason
	Sim.clear_pending()
	_reload_scene(reason)


func _on_post_resolve(_tick: int) -> void:
	if not checkpoints_enabled():
		_pending = {}
		return
	if player() != null:
		stats.play_time_s = float(stats.play_time_s) + Sim.DT
	if _pending.is_empty():
		return
	if checkpoint_blockers(bool(_pending.get("completion", false))).is_empty():
		_commit_checkpoint(str(_pending.reason), str(_pending.respawn))


# --------------------------------------------------------------------------- progress (P20)

## A new game's progress.
static func default_progress() -> Dictionary:
	return {"prologue_complete": false, "world_entered": false, "levels_visited": [], "tracked_quest": ""}


## A save's progress block, normalised (missing or mistyped keys get their defaults).
static func progress_from(raw: Variant) -> Dictionary:
	var out := default_progress()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	for key: String in ["prologue_complete", "world_entered"]:
		if typeof(d.get(key)) == TYPE_BOOL:
			out[key] = d[key]
	if typeof(d.get("levels_visited")) == TYPE_ARRAY:
		var visited: Array = []
		for v: Variant in d.levels_visited:
			if typeof(v) == TYPE_STRING and str(v) != "" and not visited.has(str(v)):
				visited.append(str(v))
		out.levels_visited = visited
	if typeof(d.get("tracked_quest")) == TYPE_STRING:
		out.tracked_quest = str(d.tracked_quest)
	return out


## The progress block a checkpoint writes: the prologue is complete once slice.completed holds;
## the tracked quest is Quests.tracked_quest_id when the property exists (P27).
func _progress_snapshot() -> Dictionary:
	var out := progress_from(progress)
	if QuestConditions.truthy(WorldState.get_flag("slice.completed")):
		out.prologue_complete = true
	if level_id == WORLD_LEVEL_ID:
		out.world_entered = true
	var quests := get_node_or_null("/root/Quests")
	if quests != null and "tracked_quest_id" in quests:
		out.tracked_quest = str(quests.get("tracked_quest_id"))
	progress = out.duplicate(true)
	return out


## Puts the saved tracked quest back into Quests.tracked_quest_id when the property exists (P27).
func _restore_tracked_quest() -> void:
	var quests := get_node_or_null("/root/Quests")
	if quests != null and "tracked_quest_id" in quests and typeof(progress.get("tracked_quest")) == TYPE_STRING:
		quests.set("tracked_quest_id", str(progress.tracked_quest))


# --------------------------------------------------------------------------- triggers

func _on_checkpoint_reached(_tick: int, checkpoint_id: String, kind: String) -> void:
	if checkpoints_enabled() and checkpoint_id != "":
		WorldState.try_set_flag(VISITED_PREFIX + checkpoint_id, true)
	request_checkpoint("waystone" if kind == "waystone" else "shrine_reached", checkpoint_id)


func _on_shrine_activated(_tick: int, shrine_id: String) -> void:
	request_checkpoint("shrine_activated", shrine_respawn(shrine_id))


func _on_shrine_rested(_tick: int, shrine_id: String) -> void:
	request_checkpoint("shrine_rested", shrine_respawn(shrine_id))


## The shrine screen's checkpoint is taken before the screen opens (ScreenStack opens it
## deferred); a blocked one waits like any other.
func _on_ui_screen_requested(screen: String, args: Dictionary) -> void:
	if screen != "shrine" or not checkpoints_enabled():
		return
	var respawn := ""
	var shrine: Variant = args.get("shrine")
	if shrine is Node and is_instance_valid(shrine):
		respawn = shrine_node_respawn(shrine)
	take_checkpoint("shrine_screen", respawn)


## Growth at a shrine (the Grow tab, the bot's shrine.grow): the shrine beside the player is the
## respawn. A debug grow away from every shrine takes no checkpoint, nor does a restore.
func _on_growth_changed(_tick: int, entity_id: String, _old_stage: int, _new_stage: int) -> void:
	if _restoring or not checkpoints_enabled():
		return
	var p := player()
	if p == null or p.entity == null or entity_id != p.entity.entity_id:
		return
	var shrine := nearest_shrine(p.global_position, SHRINE_GROWTH_RADIUS_M)
	if shrine == null:
		return
	request_checkpoint("growth", shrine_node_respawn(shrine))


## M8 gate (F15): talent_learned / ancestry_chosen / loadout_changed (two arguments) and
## attributes_changed (one) while a shrine's screen is open.
func _on_shrine_choice_2(_tick: int, _id: String) -> void:
	_note_shrine_choice()


func _on_shrine_choice_1(_tick: int) -> void:
	_note_shrine_choice()


## A talent learned, the ancestry chosen, attribute points spent or the loadout changed in a shrine's
## screen (or the ancestry screen it opened): the screens call the first three permanent, so the
## shrine's checkpoint is taken again - with the shrine as the respawn, at the end of this frame (one
## checkpoint however many changed together: choose_ancestry also changes the attributes), the
## shrine's own screens not holding it back. A choice made anywhere else waits for the next
## checkpoint, as XP does.
func _note_shrine_choice() -> void:
	if _restoring or not checkpoints_enabled():
		return
	var screen := open_shrine_screen()
	if screen == null:
		return
	var respawn := ""
	if screen.shrine != null and is_instance_valid(screen.shrine):
		respawn = shrine_node_respawn(screen.shrine)
	request_checkpoint("shrine_choice", respawn)
	if not _shrine_choice_queued:
		_shrine_choice_queued = true
		call_deferred("_commit_shrine_choice")


## Takes the queued shrine-choice checkpoint unless something besides the shrine's own screens holds
## it back (an aware enemy near the shrine: it then waits like any other request).
func _commit_shrine_choice() -> void:
	_shrine_choice_queued = false
	if _pending.is_empty() or not checkpoints_enabled():
		return
	if shrine_choice_blockers().is_empty():
		_commit_checkpoint(str(_pending.reason), str(_pending.respawn))


## The shrine screen open in a screen stack now (under the ancestry screen it may have opened), or
## null.
func open_shrine_screen() -> ShrineScreen:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group(ScreenStack.GROUP):
		var s := n as ScreenStack
		if s == null or not is_instance_valid(s) or not s.is_open("shrine"):
			continue
		for c in s.get_children():
			if c is ShrineScreen and s.has_screen(c as UiScreen):
				return c as ShrineScreen
	return null


## checkpoint_blockers() for a choice made in a shrine's screen: the shrine screen and the ancestry
## screen over it are where the choice is made, not a reason to wait; any other screen still is.
func shrine_choice_blockers() -> PackedStringArray:
	var own_screens := _only_shrine_screens_open()
	var out := PackedStringArray()
	for b in checkpoint_blockers():
		if b == "screen" and own_screens:
			continue
		out.append(b)
	return out


## True when a shrine screen is open and every open screen is it or the ancestry screen.
func _only_shrine_screens_open() -> bool:
	if not is_inside_tree():
		return false
	var shrine_open := false
	for n in get_tree().get_nodes_in_group(ScreenStack.GROUP):
		var s := n as ScreenStack
		if s == null or not is_instance_valid(s) or not s.any_open():
			continue
		var own := (1 if s.is_open("shrine") else 0) + (1 if s.is_open("ancestry") else 0)
		if s.count() > own:
			return false
		shrine_open = shrine_open or s.is_open("shrine")
	return shrine_open


## The Ogre King's death moves the respawn to the Kingsfall shrine - but not on another campaign
## level (P20: a world boss keeps the respawn; test levels keep today's rule).
## M8 gate (fix-up 1, F38): a boss's end is a completion request (request_checkpoint): its brood or
## guards still aware within 40 m (the Matriarch's den whelps, her summoned ones) do not hold it back,
## and a quit to the title commits it if something else does - decision 13 never loses a boss kill.
## The respawn stays at a shrine or waystone (or the Kingsfall shrine), so it cannot trap the giant.
func _on_boss_defeated(_tick: int, _boss_id: String) -> void:
	var other_level := is_campaign() and level_id != "" and level_id != VALLEY_LEVEL_ID \
		and not level_id.begins_with("res://")
	request_checkpoint("boss_defeated", "" if other_level else KINGSFALL_RESPAWN, true)


## M8 gate (F38): a boss driven out (the Matriarch's flight: boss_disengaged "fled") ends its fight
## as a kill does, so it is checkpointed like boss_defeated (decision 13: a checkpoint never loses a
## boss's end) - the respawn unchanged, and no victory cue (only boss_defeated has one); a completion
## request like the kill's (fix-up 1: her aware whelps held it back). "left" (the giant walked out;
## the boss resets) takes none. M8 release (R1): "yielded_talk" (Harrok's talk ending chosen while his
## duel is engaged: MootArena ends the duel without a victory) ends the fight too and takes the same
## request ("boss_yielded_talk").
func _on_boss_disengaged(_tick: int, _boss_id: String, reason: String) -> void:
	if BOSS_END_REASONS.has(reason):
		request_checkpoint(str(BOSS_END_REASONS[reason]), "", true)


## The quests' checkpoints (decision 13: "after every quest.main stage").
## M8 gate fix-up 1 (N4.2): the world's main thread was never checkpointed - only quest.main (the
## Valley's) was compared, so quest.world_main's stages, the oaths won and the quests a dialogue starts
## were lost to a quit or a death. Now:
##   * quest.main's stages (the Valley; or a test's main quest, Quests.main_quest_id): as before, an
##     ordinary request (aware enemies within 40 m hold it back);
##   * quest.world_main's stages and an oath won (a quest.oath_<x> completed): completion requests,
##     as a boss's end - the main thread moves on where enemies are about (the war camp after its
##     sabotage, the Moot after the duel), and a quit to the title commits one still waiting;
##   * on another campaign level than the Valley (the world), every other quest's start, stage and
##     completion (Ulfra's plea starting the siege, a side quest's reward): an ordinary request -
##     M9 gate (lane ironreg) but the start of an oath's road (settles_an_oath: the crown's breach,
##     quest.iron_regiment, which Fort Aldmere's gate falling starts, and its sabotage, quest.war_engines,
##     which the deserters' word or the first of its engines wrecked starts): a completion request, as
##     the oath it leads to. The gate falls with its garrison aware about the giant: the ordinary request
##     waited on them, then on the battle he walked into, and a death in the battle dropped it - every
##     death reloaded the fort gate's waystone with the gate whole, and he broke it again under the
##     garrison's arrows and bolts before each attempt (docs/BALANCE_LOG.md, "M9 gate (lane ironreg)").
## The respawn stays where it is.
func _on_quest_stage_changed(_tick: int, quest_id: String, _stage_id: String) -> void:
	if quest_id == WORLD_MAIN_QUEST_ID:
		request_checkpoint("quest_stage", "", true)
	elif quest_id == MAIN_QUEST_ID or quest_id == _main_quest_id():
		request_checkpoint("quest_stage")
	elif _world_quests_checkpoint():
		request_checkpoint("quest_stage")


func _on_quest_started(_tick: int, quest_id: String) -> void:
	if quest_id != WORLD_MAIN_QUEST_ID and _world_quests_checkpoint():
		request_checkpoint("quest_started", "", settles_an_oath(quest_id))   # M9 gate (lane ironreg)


## M9 gate (lane ironreg): true when a stage of quest `quest_id` writes an oath's done flag (oath.<x>.done): the
## quest is one of that oath's roads (see _on_quest_stage_changed's notes).
static func settles_an_oath(quest_id: String) -> bool:
	for st: Variant in GameData.get_record(quest_id).get("stages", []):
		var writes: Variant = (st as Dictionary).get("set_flags", {}) if typeof(st) == TYPE_DICTIONARY else {}
		if typeof(writes) != TYPE_DICTIONARY:
			continue
		for flag: Variant in writes:
			if str(flag).begins_with("oath.") and str(flag).ends_with(".done"):
				return true
	return false


func _on_quest_completed(_tick: int, quest_id: String) -> void:
	if quest_id == MAIN_QUEST_ID or quest_id == WORLD_MAIN_QUEST_ID or quest_id == _main_quest_id():
		return   # the main quest's end: Quests requests its completion checkpoint ("quest_complete")
	if quest_id.begins_with(OATH_QUEST_PREFIX):
		request_checkpoint("oath_won", "", true)
	elif _world_quests_checkpoint():
		request_checkpoint("quest_completed")


## Quests.main_quest_id (quest.main until quest.world_main leads; a test's fixture), else quest.main.
func _main_quest_id() -> String:
	var quests := get_node_or_null("/root/Quests")
	if quests != null and "main_quest_id" in quests:
		return str(quests.get("main_quest_id"))
	return MAIN_QUEST_ID


## True on a campaign level other than the Valley (the world): every quest's progress takes a
## checkpoint there (fix-up 1, N4.2). The Valley and test levels keep decision 13's table.
func _world_quests_checkpoint() -> bool:
	return is_campaign() and level_id != "" and level_id != VALLEY_LEVEL_ID and not level_id.begins_with("res://")


func _on_reload_checkpoint_requested(reason: String) -> void:
	reload_checkpoint(reason)


func _on_mode_change_requested(mode_name: String, options: Dictionary) -> void:
	last_mode_result = change_mode(mode_name, options)


func _on_entity_died(_tick: int, entity_id: String, _killer_id: String) -> void:
	if not checkpoints_enabled():
		return
	var p := player()
	if p != null and p.entity != null and entity_id == p.entity.entity_id:
		stats.deaths = int(stats.deaths) + 1


## The checkpoint id of a shrine named by a shrine event: the id itself when a checkpoint marker
## has it (the shrine's world id), else the world id of the shrine node whose shrine_id (record
## id) or world_id matches; "" when nothing matches (the respawn then stays as it is).
func shrine_respawn(shrine_id: String) -> String:
	if shrine_id == "":
		return ""
	if find_checkpoint(shrine_id) != null:
		return shrine_id
	for n in get_tree().get_nodes_in_group("shrines"):
		if ("shrine_id" in n and str(n.get("shrine_id")) == shrine_id) \
				or ("world_id" in n and str(n.get("world_id")) == shrine_id):
			return shrine_node_respawn(n)
	return ""


## A shrine node's checkpoint id: its world_id, else the id of its SpawnPoint marker.
static func shrine_node_respawn(shrine: Node) -> String:
	if "world_id" in shrine and str(shrine.get("world_id")) != "":
		return str(shrine.get("world_id"))
	for child in shrine.get_children():
		if child is CheckpointMarker and (child as CheckpointMarker).checkpoint_id != "":
			return (child as CheckpointMarker).checkpoint_id
	return ""


## The nearest node of group "shrines" within radius_m of pos, or null.
func nearest_shrine(pos: Vector3, radius_m: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius_m
	for n in get_tree().get_nodes_in_group("shrines"):
		var s := n as Node3D
		if s == null or not s.is_inside_tree():
			continue
		var d := s.global_position.distance_to(pos)
		if d <= best_d:
			best = s
			best_d = d
	return best


# --------------------------------------------------------------------------- queries

## The player of the current level: the one on_level_ready was given while it lives, else the
## first node of group "player" (tests), else null.
func player() -> GiantPlayer:
	var p: Object = _player_ref.get_ref() if _player_ref != null else null
	if p != null and is_instance_valid(p) and (p as Node).is_inside_tree():
		return p as GiantPlayer
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as GiantPlayer


## The queued checkpoint ({"reason", "respawn", "tick", "completion"}) or {} when none waits.
func pending_checkpoint() -> Dictionary:
	return _pending.duplicate()


## The display name of a checkpoint of the current (or the given) level (P20): its world index
## entry's, else its node's (a shrine's record name, a waystone's display_name); "" when unknown.
func checkpoint_display_name(checkpoint_id: String, p_level_id := "") -> String:
	if checkpoint_id == "":
		return ""
	var lv := p_level_id if p_level_id != "" else save_level_id()
	var title := WorldIndex.display_name_in(lv, checkpoint_id)
	if title != "":
		return title
	var marker := find_checkpoint(checkpoint_id)
	if marker == null:
		return ""
	if marker is Waystone and (marker as Waystone).display_name != "":
		return (marker as Waystone).display_name
	var parent := marker.get_parent()
	if parent is Shrine:
		return (parent as Shrine).display_name()
	return ""


## True while the current level's player is dead (a reload from the menu or F9 then gets the
## death floor).
func _player_dead() -> bool:
	var p := player()
	return p != null and p.controller != null and p.controller.state == CombatController.State.DEAD


func mode_name() -> String:
	return MODE_NAMES[mode]


func _level() -> Node:
	var l: Object = _level_ref.get_ref() if _level_ref != null else null
	return l as Node if l != null and is_instance_valid(l) else null


func _modal_screen_open() -> bool:
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group(ScreenStack.GROUP):
		var s := n as ScreenStack
		if s != null and is_instance_valid(s) and s.any_open():
			return true
	return false


static func _zero_stats() -> Dictionary:
	return {"deaths": 0, "checkpoint_loads": 0, "play_time_s": 0.0}


static func _stats_from(raw: Variant) -> Dictionary:
	var out := _zero_stats()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	for key: String in ["deaths", "checkpoint_loads"]:
		if SchemaUtil.is_number(d.get(key)):
			out[key] = maxi(0, int(d[key]))
	if SchemaUtil.is_number(d.get("play_time_s")):
		out.play_time_s = maxf(0.0, float(d.play_time_s))
	return out


static func _join_message(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return a + " " + b


## Lines for the F3 debug panel (group debug_info_providers).
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var pending := ("  pending %s" % _pending.reason) if not _pending.is_empty() else ""
	lines.append("SESSION %s  level %s (%s)  respawn %s  checkpoints %s%s" % [mode_name(),
		level_scene_path().get_file(), level_id if level_id != "" else "-", respawn_id if respawn_id != "" else "-",
		"on" if checkpoints_enabled() else "off", pending])
	if checkpoints_enabled():
		var blockers := checkpoint_blockers()
		lines.append("        taken %d  loads %d  deaths %d  play %.0f s  saving %s  blockers %s" % [
			checkpoints_taken, int(stats.checkpoint_loads), int(stats.deaths), float(stats.play_time_s),
			"on" if _writes_enabled() else "off", ", ".join(blockers) if not blockers.is_empty() else "-"])
	return lines


## ResetHooks.BEFORE_EACH: the sandbox, no writes, the test save folder (emptied), no pending
## restore or checkpoint, and scene reloads replaced by the scene_reloads log.
func reset_for_tests() -> void:
	mode = Mode.SANDBOX
	level_override = ""
	_cli_level_override = ""
	_cli_start = ""
	level_id = ""
	character = {}
	checkpoint_doc = {}
	pending_restore = false
	persist = false
	respawn_id = ""
	test_checkpoints = false
	stats = _zero_stats()
	progress = {}
	allow_scene_reload = false
	scene_reloads.clear()
	last_mode_result = {}
	last_travel_result = {}
	checkpoints_taken = 0
	last_load_message = ""
	entered_log.clear()
	_pending = {}
	_load_reason = ""
	_reload_floor = {}
	_restoring = false
	_reload_queued = false
	_player_ref = null
	_level_ref = null
	_start_override = ""
	_visit_activated.clear()
	_respawn_blockers.clear()
	_blocker_level = ""
	_entering = {}
	_shrine_choice_queued = false
	_stop_polling_entered()
	SaveSlots.path_override = TEST_SAVE_PATH
	SaveSlots.delete_slot(true)
