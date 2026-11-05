extends SceneTree
## The Valley screenshot tour (P18). It starts the game exactly as the command line asks (normally
## the Valley bot of P17a: `--mode=valley --new-game --scenario=valley ...`), lets it play in a real,
## rendered window, and saves a screenshot at the moments a player would want to see: the start, a
## telegraph aimed at the giant (each enemy attack once or twice, part-way through its windup), grabs
## and throws, Boulder Hurl, growth, arriving in each district, the practice gate cracking, the boss,
## the tree, the Deadfall, a level-up and the end screen; plus one every --tour-every seconds.
## It changes nothing in the game's state: it listens to Events, reads the viewport and keeps the
## mouse captured as a player's would be (the HUD otherwise asks for a click). At the end, when the
## slice completes, it stops the Autopilot and the bot (process mode DISABLED), so the end screen is
## drawn instead of the run quitting at once, saves that shot and quits.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 \
##     --audio-driver Dummy -s res://tools/valley_tour.gd -- --no-user-settings \
##     --save-dir=user://tour_saves --mode=valley --new-game --scenario=valley --bot-assist \
##     --bot-village=help_cache --autoplay=2400 --tour-dir=/absolute/folder
##
## Options (after --, besides the game's own): --tour-dir=PATH (default user://tour),
## --tour-every=S (a plain shot every S simulated seconds, default 30; 0 = none),
## --tour-max=N (stop after N shots, default 150). Run it without --fixed-fps: the simulation then
## keeps close to real time while a software renderer draws a few frames a second.
## Shots are PNG files named <nnn>_<moment>.png; "TOUR_SHOT <path> tick=<t>" is printed for each.

const MAIN_SCENE := "res://scenes/main.tscn"
const TICKS_PER_S := 60
## Stopped when the slice completes (by path: this script loads before the autoloads exist, so it
## must not name classes whose scripts use them).
const STOP_ON_END := ["res://scripts/debug/autopilot.gd", "res://scripts/debug/valley_bot.gd"]

var _dir := "user://tour"
var _every_s := 30.0
var _max_shots := 150
var _queue: Array = []        # [{"tick": int, "name": String}], due shots
var _counts := {}             # moment key -> shots taken
var _last_tick := {}          # moment key -> tick of its last shot
var _shots := 0
var _busy := false
var _connected := false
var _next_plain_tick := 0
var _start_done := false
var _ending := false
var _end_frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour-dir="):
			_dir = a.substr(11)
		elif a.begins_with("--tour-every="):
			_every_s = maxf(0.0, float(a.substr(13)))
		elif a.begins_with("--tour-max="):
			_max_shots = maxi(1, int(a.substr(11)))
	DirAccess.make_dir_recursive_absolute(_dir)
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)
	change_scene_to_file(MAIN_SCENE)


func _sim_tick() -> int:
	var sim := root.get_node_or_null("Sim")
	return int(sim.tick) if sim != null else 0


func _connect() -> void:
	var ev := root.get_node_or_null("Events")
	if ev == null:
		return
	_connected = true
	ev.telegraph_started.connect(_on_telegraph)
	ev.grab_started.connect(func(_t, _h, _target): _plan("grab", 0.4, 2))
	ev.grab_ended.connect(func(_t, _h, _target, reason):
		if reason == "thrown":
			_plan("throw", 0.25, 2))
	ev.projectile_spawned.connect(_on_projectile)
	ev.ability_started.connect(_on_ability)
	ev.growth_changed.connect(func(_t, entity_id, _old, new_stage):
		if entity_id == "player":
			_plan("growth_stage_%d" % new_stage, 2.5, 1))
	ev.area_entered.connect(func(_t, area_id, _e):
		_plan("area_" + str(area_id).get_extension(), 1.5, 1))
	ev.object_stage_changed.connect(func(_t, world_id, _i, stage_id):
		_plan("%s_%s" % [str(world_id).get_extension(), stage_id], 0.3, 1))
	ev.object_destroyed.connect(func(_t, world_id, _by):
		var short := str(world_id).get_extension()
		if short in ["practice_gate", "deadfall", "barricade", "cairn"]:
			_plan(short + "_destroyed", 0.4, 1))
	ev.boss_engaged.connect(func(_t, _b): _plan("boss_engaged", 2.0, 1))
	ev.boss_phase_changed.connect(func(_t, _b, phase): _plan("boss_phase_%d" % phase, 0.7, 1))
	ev.boss_defeated.connect(func(_t, _b): _plan("boss_defeated", 1.0, 1))
	ev.weapon_equipped.connect(func(_t, entity_id, weapon_id):
		if entity_id == "player":
			_plan("weapon_" + str(weapon_id).get_extension(), 1.0, 1))
	ev.level_changed.connect(func(_t, _old, new_level): _plan("level_%d" % new_level, 0.3, 1))
	ev.upgrade_applied.connect(func(_t, _from, to): _plan("reforged_" + str(to).get_extension(), 0.5, 1))
	ev.dialogue_started.connect(func(_t, _d, _npc): _plan("dialogue", 0.1, 1))
	ev.faction_changed.connect(func(_t, _f, state): _plan("village_" + str(state), 1.0, 1))
	ev.slice_completed.connect(_on_slice_completed)


## Keeps the run alive for the end screen: the Autopilot would quit on its next tick and the bot
## would close the screen. Connected before either of them (at the first physics frame).
func _on_slice_completed(_tick: int) -> void:
	_ending = true
	for n in root.find_children("*", "", true, false):
		var script: Script = n.get_script()
		if script != null and script.resource_path in STOP_ON_END:
			n.process_mode = Node.PROCESS_MODE_DISABLED


func _on_telegraph(_tick: int, _actor_id: String, action_id: String, target_id: String, _shape: String,
		_origin: Vector3, _yaw: float, _radius: float, _length: float, duration_s: float) -> void:
	if target_id != "player":
		return
	# Part-way through the windup: the decal is half full and the attacker is in its wind-up pose.
	_plan("telegraph_" + action_id.get_extension(), duration_s * 0.55, 2, 20.0)


func _on_projectile(_tick: int, _id: int, owner_id: String, action_id: String, _pos: Vector3,
		_vel: Vector3, _visual: String) -> void:
	if owner_id == "player":
		_plan("shot_" + action_id.get_extension(), 0.3, 2, 30.0)


func _on_ability(_tick: int, actor_id: String, action_id: String, _instance: int) -> void:
	if actor_id != "player":
		return
	var short := action_id.get_extension()
	if short in ["heavy_footfall", "sweeping_blow", "thunder_roar", "titan_surge", "stone_skin",
			"ancestral_mend", "crushing_grip"]:
		_plan("ability_" + short, 0.3, 1)


## Schedules a shot `delay_s` simulated seconds from now, at most `max_count` times per key and
## no sooner than `gap_s` after the last one of that key.
func _plan(key: String, delay_s: float, max_count: int, gap_s: float = 0.0) -> void:
	var now := _sim_tick()
	if int(_counts.get(key, 0)) >= max_count:
		return
	if _last_tick.has(key) and now - int(_last_tick[key]) < int(gap_s * TICKS_PER_S):
		return
	_counts[key] = int(_counts.get(key, 0)) + 1
	_last_tick[key] = now
	_queue.append({"tick": now + int(round(delay_s * TICKS_PER_S)), "name": key})


func _on_physics_frame() -> void:
	if not _connected:
		_connect()
	var now := _sim_tick()
	if _every_s > 0.0 and now >= _next_plain_tick and now > 3 * TICKS_PER_S:
		if _next_plain_tick > 0:
			_queue.append({"tick": now, "name": "every_%ds" % int(now / TICKS_PER_S)})
		_next_plain_tick = now + int(_every_s * TICKS_PER_S)
	if not _start_done and now >= 3 * TICKS_PER_S:
		_start_done = true
		_queue.append({"tick": now, "name": "start"})


func _on_process_frame() -> void:
	# A player's mouse is captured while they play (the HUD otherwise asks for a click). Tool runs
	# never capture it themselves.
	if not paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _busy or _shots >= _max_shots:
		if _shots >= _max_shots and not _busy:
			quit()
		return
	# The end screen: a few frames for its layout, then the last shot.
	if _ending and _screen_open("end"):
		_end_frames += 1
		if _end_frames >= 4:
			_busy = true
			await RenderingServer.frame_post_draw
			_save(root.get_texture().get_image(), "end_screen")
			quit()
		return
	var now := _sim_tick()
	for i in _queue.size():
		if int(_queue[i].tick) <= now:
			var name := str(_queue[i].name)
			_queue.remove_at(i)
			_shoot(name)
			return


func _screen_open(screen_name: String) -> bool:
	for n in get_nodes_in_group("screen_stack"):
		if n.has_method("is_open") and n.is_open(screen_name):
			return true
	return false


func _shoot(name: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), name)
	_busy = false


func _save(img: Image, name: String) -> void:
	_shots += 1
	var path := _dir.path_join("%03d_%s.png" % [_shots, name.validate_filename()])
	img.save_png(path)
	print("TOUR_SHOT %s tick=%d" % [path, _sim_tick()])
