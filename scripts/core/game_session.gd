extends Node
## Game session (autoload "GameSession", plan §2.9, §3.6, decisions 13-15): the game mode, the
## live character state, the last checkpoint document, and the flows between them - title,
## New Game, Continue, the sandbox, checkpoints, death and reload. Autoload order: Events,
## GameData, Settings, WorldState, GameSession, (Quests,) Sim.
##
## Modes. TITLE shows the title screen only. SANDBOX loads the M1 sandbox (or the --level
## scene) with the player record as it is; resets clear the world (WorldState.clear) and reload.
## VALLEY loads the Valley (or the --level scene) with `character` applied; it never clears the
## world on death but reloads the last checkpoint. Every mode change and reload is a reload of
## main.tscn: main.gd builds what `mode` asks for and calls on_level_ready(level, player).
##
## Checkpoints exist only when checkpoints_enabled() (the Valley, or a test level that sets
## test_checkpoints). Triggers (GameSession listens to the events; nothing calls it directly):
##   checkpoint_reached (a shrine's first activation, a waystone)   -> respawn: that marker
##   shrine_activated, shrine_rested, ui_screen_requested("shrine")  -> respawn: that shrine
##   growth_changed for the player beside a shrine                   -> respawn: that shrine
##   boss_defeated                                                   -> respawn: valley.shrine.kingsfall
##   quest_stage_changed for quest.main                              -> respawn unchanged
## A request waits (one pending request; a later one replaces the reason and keeps the newest
## respawn) while checkpoint_blockers() is not empty: the player is dead, grabbed, executing or
## holding something, a modal screen is open, or an enemy within 40 m is aware of the player.
## It is retried every tick from a Sim POST_RESOLVE hook (order 200). The shrine screen's
## checkpoint is taken at once, before the screen opens. Only the Valley writes the save slot
## (and only with `persist`); a test level's checkpoints in the sandbox stay in memory.
##
## Death in the Valley: main shows "Enter / A: load last checkpoint" and emits
## reload_checkpoint_requested("death"): the checkpoint's world and character come back, the
## resources are raised to progression.default.death_reload_floor (health 60 %, stamina 100 %,
## essence 50 %; fury 0), and the scene reloads. Continue restores a save exactly.
##
## Tests: reset_for_tests() (ResetHooks.BEFORE_EACH) puts the session in the sandbox, turns
## writes off, points SaveSlots at user://test_saves/ and replaces scene reloads with a log
## (scene_reloads), so a test drives the flow and instantiates the level itself.

enum Mode { TITLE, SANDBOX, VALLEY }

const MODE_NAMES := ["title", "sandbox", "valley"]
const SANDBOX_SCENE := "res://scenes/world/sandbox_arena.tscn"
const VALLEY_LEVEL_ID := "level.valley"
const PROGRESSION_ID := "progression.default"
const PLAYER_ID := "player.giant"
const MAIN_QUEST_ID := "quest.main"
const KINGSFALL_RESPAWN := "valley.shrine.kingsfall"
## An aware enemy this close to the player defers a checkpoint (decision 13).
const AWARE_BLOCK_RADIUS_M := 40.0
## growth_changed counts as "growth at a shrine" when a shrine is at most this far away.
const SHRINE_GROWTH_RADIUS_M := 25.0
const HOOK_ORDER := 200
const TEST_SAVE_PATH := "user://test_saves/valley_1.json"
const DEFAULT_DEATH_FLOOR := {"health": 0.6, "stamina": 1.0, "essence": 0.5}
const VALLEY_MISSING := "Valley not built yet"
## checkpoint_saved messages for a checkpoint that was taken but not written.
const NO_SAVING := "saving is off"
const MEMORY_ONLY := "kept in memory"
const MAX_RELOAD_LOG := 64

var mode: int = Mode.SANDBOX
## A scene that replaces the mode's level (--level=res://...tscn; tests).
var level_override := ""
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

## False in tests: reloads are only logged in scene_reloads (the test runner is the scene).
var allow_scene_reload := true
## The reason of every scene reload requested (new_game, continue, death, title, ...).
var scene_reloads: Array[String] = []
## The result of the last mode_change_requested ({"ok", "message"}); the title screen reads it.
var last_mode_result: Dictionary = {}
## How many checkpoints were committed (this process).
var checkpoints_taken := 0
## The message of the last Continue read ("Recovered ...", dropped ids), "" when clean.
var last_load_message := ""

var _configured := false
## The --level scene of the command line ("" = none). A Continue may replace level_override with
## its save's scene; quitting to the title, the sandbox and a New Game go back to this one (P16).
var _cli_level_override := ""
var _pending: Dictionary = {}       ## {"reason", "respawn", "tick"} of the queued checkpoint
var _load_reason := ""              ## why pending_restore is set: new_game|continue|death|debug|menu
var _reload_floor: Dictionary = {}  ## death_reload_floor to apply on the next restore
var _restoring := false             ## inside on_level_ready (growth events there are not growth)
var _reload_queued := false
var _player_ref: WeakRef = null
var _level_ref: WeakRef = null


func _ready() -> void:
	add_to_group("debug_info_providers")
	configure_from_args(OS.get_cmdline_user_args())
	Events.checkpoint_reached.connect(_on_checkpoint_reached)
	Events.shrine_activated.connect(_on_shrine_activated)
	Events.shrine_rested.connect(_on_shrine_rested)
	Events.ui_screen_requested.connect(_on_ui_screen_requested)
	Events.growth_changed.connect(_on_growth_changed)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.quest_stage_changed.connect(_on_quest_stage_changed)
	Events.reload_checkpoint_requested.connect(_on_reload_checkpoint_requested)
	Events.mode_change_requested.connect(_on_mode_change_requested)
	Events.entity_died.connect(_on_entity_died)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_post_resolve, HOOK_ORDER)


# --------------------------------------------------------------------------- command line

## Reads the command-line options once per process (later calls do nothing); see parse_args.
func configure_from_args(args: PackedStringArray) -> void:
	if _configured:
		return
	_configured = true
	apply_args(parse_args(args))


## The session options in `args` (the user args after "--"):
##   --mode=title|sandbox|valley   default title; without --mode: valley with --new-game or
##                                 --continue, else sandbox when --autoplay, --scenario or --level
##                                 is given (so the M1 tools keep booting the sandbox)
##   --new-game / --continue       how --mode=valley starts (neither: continue when a save
##                                 loads, else a new game)
##   --level=res://...tscn         the level scene to load instead of the mode's own
##   --save-dir=user://...         the folder of the save slot (keeps saving on with
##                                 --no-user-settings)
##   --no-user-settings            no writes to the player's files (persist false)
## Returns {"mode", "mode_given", "new_game", "continue", "level", "save_dir",
## "no_user_settings", "tool_run", "persist", "unknown_mode"}.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"mode": "title", "mode_given": false, "new_game": false, "continue": false,
		"level": "", "save_dir": "", "no_user_settings": false, "tool_run": false, "unknown_mode": ""}
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
		elif arg == "--no-user-settings":
			out.no_user_settings = true
		elif arg.begins_with("--autoplay=") or arg.begins_with("--scenario="):
			out.tool_run = true
	if not out.mode_given:
		if out.new_game or out["continue"]:
			out.mode = "valley"
		elif out.tool_run or out.level != "":
			out.mode = "sandbox"
	if not (str(out.mode) in MODE_NAMES):
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
	if str(o.get("unknown_mode", "")) != "":
		push_warning("GameSession: unknown --mode=%s (title | sandbox | valley); showing the title" % o.unknown_mode)
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
					_begin_new_valley()
				else:
					push_warning("GameSession: %s (no level.valley scene); showing the title" % VALLEY_MISSING)
					mode = Mode.TITLE
		_:
			mode = Mode.TITLE


# --------------------------------------------------------------------------- modes and levels

## The scene main.gd loads for the current mode ("" for the title, or when the Valley does not
## exist yet).
func level_scene_path() -> String:
	if level_override != "":
		return level_override
	match mode:
		Mode.SANDBOX:
			return SANDBOX_SCENE
		Mode.VALLEY:
			return scene_for_level(VALLEY_LEVEL_ID)
	return ""


func is_valley() -> bool:
	return mode == Mode.VALLEY


func checkpoints_enabled() -> bool:
	return is_valley() or test_checkpoints


## True when New Game can start: the Valley scene (or the --level scene) exists.
func valley_available() -> bool:
	var path := level_override if level_override != "" else scene_for_level(VALLEY_LEVEL_ID)
	return path != "" and ResourceLoader.exists(path)


## The scene of a save's "level": a res:// scene path itself, or a level record's scene.
func scene_for_level(level_id: String) -> String:
	if level_id.begins_with("res://"):
		return level_id
	var rec := GameData.get_record(level_id)
	return str(rec.get("scene", "")) if str(rec.get("type", "")) == "level" else ""


## True when a save document's level can be loaded by this build.
func save_level_available(doc: Dictionary) -> bool:
	var scene := scene_for_level(str(doc.get("level", VALLEY_LEVEL_ID)))
	return scene != "" and ResourceLoader.exists(scene)


func has_checkpoint() -> bool:
	return not checkpoint_doc.is_empty()


## The level id written into save documents: the --level scene, the Valley's record id, or the
## loaded level's scene path.
func current_level_id() -> String:
	if level_override != "":
		return level_override
	if is_valley():
		return VALLEY_LEVEL_ID
	var level := _level()
	if level != null and level.scene_file_path != "":
		return level.scene_file_path
	return SANDBOX_SCENE


## Title and pause screens emit Events.mode_change_requested(mode, options); this is what it
## does. mode: "title" | "sandbox" | "valley" (options: {"new_game": true} or
## {"continue": true}; neither = continue when a save loads, else a new game).
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


## The slice's completion checkpoint, if it still waits (something other than an aware enemy held
## it back), is committed before a quit to the title clears the session (P17a, M4 review: Quit to
## title on the end screen lost it). A dead giant is never saved.
func _commit_pending_completion() -> void:
	if _pending.is_empty() or not bool(_pending.get("completion", false)) or not checkpoints_enabled():
		return
	if _player_dead():
		return
	_commit_checkpoint(str(_pending.reason), str(_pending.respawn))


## A sandbox reset (death restart, F5, the pause menu, the autopilot): forget every world change
## and checkpoint of this level and reload it.
func restart_sandbox(reason: String) -> void:
	_clear_session()
	_reload_scene(reason)


func _begin_new_valley() -> void:
	mode = Mode.VALLEY
	WorldState.clear()
	Sim.clear_pending()
	character = CharacterState.new_game(GameData.get_record(PROGRESSION_ID), GameData.get_record(PLAYER_ID))
	checkpoint_doc = {}
	respawn_id = ""
	stats = _zero_stats()
	_pending = {}
	_reload_floor = {}
	last_load_message = ""
	pending_restore = true
	_load_reason = "new_game"


func _begin_continue() -> Dictionary:
	if not persist:
		return {"ok": false, "message": "Continue is off: saving is off for this run."}
	var read := SaveSlots.read()
	if not read.ok:
		return {"ok": false, "message": str(read.message) if str(read.message) != "" else "No saved game yet."}
	var doc: Dictionary = read.data
	var level_id := str(doc.get("level", VALLEY_LEVEL_ID))
	if not save_level_available(doc):
		return {"ok": false, "message": "The saved level is not in this build (%s)." % level_id}
	var world: Dictionary = doc.get("world", {})
	if not WorldState.from_save_dict(world):
		return {"ok": false, "message": "The save's world state could not be loaded."}
	level_override = level_id if level_id.begins_with("res://") else ""
	mode = Mode.VALLEY
	character = (doc.character as Dictionary).duplicate(true)
	checkpoint_doc = doc
	respawn_id = str((doc.get("checkpoint", {}) as Dictionary).get("respawn", ""))
	stats = _stats_from(doc.get("stats", {}))
	stats.checkpoint_loads = int(stats.checkpoint_loads) + 1
	_pending = {}
	_reload_floor = {}
	last_load_message = str(read.message)
	pending_restore = true
	_load_reason = "continue"
	Sim.clear_pending()
	return {"ok": true, "message": str(read.message)}


func _clear_session() -> void:
	WorldState.clear()
	Sim.clear_pending()
	character = {}
	checkpoint_doc = {}
	respawn_id = ""
	pending_restore = false
	stats = _zero_stats()
	_pending = {}
	_load_reason = ""
	_reload_floor = {}


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

## main.gd calls this after it added the level, the HUD and the screen stack. With a pending
## restore it moves the player to the respawn marker (position, spawn_transform, facing and the
## camera yaw), applies `character`, then the death floor after a death. A New Game keeps the
## scene's Player position and takes the first checkpoint. A checkpointed level started without
## a session document (a test level in the sandbox) takes a first in-memory checkpoint.
func on_level_ready(level: Node, player: GiantPlayer) -> void:
	_level_ref = weakref(level) if level != null else null
	_player_ref = weakref(player) if player != null else null
	if player == null:
		return
	if pending_restore:
		pending_restore = false
		var reason := _load_reason
		_load_reason = ""
		_restoring = true
		if reason != "new_game":
			var marker := find_checkpoint(respawn_id)
			if marker != null:
				place_player(player, marker.spawn_transform())
		player.apply_character_state(character)
		_apply_level_exempt(player, character)
		if not _reload_floor.is_empty():
			apply_reload_floor(player, _reload_floor)
			_reload_floor = {}
		character = CharacterState.normalize(player.capture_character_state())
		_restoring = false
		if reason == "new_game":
			if respawn_id == "":
				respawn_id = _start_checkpoint(level)
			_commit_checkpoint("new_game", "")
		else:
			Events.checkpoint_loaded.emit(Sim.tick, respawn_id, reason if reason != "" else "load")
	elif checkpoints_enabled() and checkpoint_doc.is_empty():
		if respawn_id == "":
			respawn_id = _start_checkpoint(level)
		_commit_checkpoint("level_start", "")


## The CheckpointMarker (or Waystone, or shrine SpawnPoint) with this id, or null.
func find_checkpoint(checkpoint_id: String) -> CheckpointMarker:
	if checkpoint_id == "" or not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("checkpoints"):
		var m := n as CheckpointMarker
		if m != null and m.is_inside_tree() and m.checkpoint_id == checkpoint_id:
			return m
	return null


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
## pending request until that is taken.
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
## screen, aware:<enemy id> (an aware enemy within 40 m), no_player. ignore_aware: leave the
## aware enemies out (the slice's completion checkpoint).
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


## The document a checkpoint stores (and writes): the character (refreshed from the player when
## there is one), the world, the respawn point, the reason and the session stats.
func snapshot_document(reason: String) -> Dictionary:
	var p := player()
	if p != null and not _restoring:
		character = CharacterState.normalize(p.capture_character_state())
	return {
		"schema_version": SaveSlots.SCHEMA_VERSION,
		"build_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"slot": SaveSlots.SLOT,
		"level": current_level_id(),
		"checkpoint": {"respawn": respawn_id, "reason": reason},
		"character": character.duplicate(true),
		"world": WorldState.to_save_dict(),
		"stats": stats.duplicate(true),
	}


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
		result.message = NO_SAVING if is_valley() else MEMORY_ONLY
	Events.checkpoint_saved.emit(Sim.tick, respawn_id, bool(result.ok), str(result.message))
	return result


## The Valley writes the slot (with persist); test levels in the sandbox never do, so they can
## never overwrite the player's save.
func _writes_enabled() -> bool:
	return persist and is_valley()


## Reloads the last checkpoint: its world and character come back and the scene reloads; the
## next on_level_ready puts the player at its respawn point. reason "death" applies the death
## floor (decision 13); "continue", "debug" and "menu" restore it exactly - unless the player is
## dead when they are asked for (P16, M3 review: the pause menu's Load last checkpoint or F9 on
## the death screen is a death reload too, so it gets the floor).
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


# --------------------------------------------------------------------------- triggers

func _on_checkpoint_reached(_tick: int, checkpoint_id: String, kind: String) -> void:
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


func _on_boss_defeated(_tick: int, _boss_id: String) -> void:
	request_checkpoint("boss_defeated", KINGSFALL_RESPAWN)


func _on_quest_stage_changed(_tick: int, quest_id: String, _stage_id: String) -> void:
	if quest_id == MAIN_QUEST_ID:
		request_checkpoint("quest_stage")


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


## Lines for the F3 debug panel (group debug_info_providers).
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var pending := ("  pending %s" % _pending.reason) if not _pending.is_empty() else ""
	lines.append("SESSION %s  level %s  respawn %s  checkpoints %s%s" % [mode_name(),
		level_scene_path().get_file(), respawn_id if respawn_id != "" else "-",
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
	character = {}
	checkpoint_doc = {}
	pending_restore = false
	persist = false
	respawn_id = ""
	test_checkpoints = false
	stats = _zero_stats()
	allow_scene_reload = false
	scene_reloads.clear()
	last_mode_result = {}
	checkpoints_taken = 0
	last_load_message = ""
	_pending = {}
	_load_reason = ""
	_reload_floor = {}
	_restoring = false
	_reload_queued = false
	_player_ref = null
	_level_ref = null
	SaveSlots.path_override = TEST_SAVE_PATH
	SaveSlots.delete_slot(true)
