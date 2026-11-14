extends SceneTree
## The world screenshot tour (P40; plan M6-M9 §3.24: "screenshots of the world - a world tour beside the
## bot, the Kingsgate shelf's view first"), after tools/valley_tour.gd (P18), which ran beside the Valley
## bot for M5's gallery, and the M8 screenshot pass's scripted placements. Two modes.
##
## Beside the bot (the default). It starts the game exactly as the command line asks - normally one of
## tools/run_bots.sh's world runs (P38) - lets the bot play in a real window, and saves a screenshot as the
## bot reaches each place: the Kingsgate shelf's view (the first shots, from the start), every point of
## interest it discovers (Brannock and Millford, the toll fort and the war camp, Fort Aldmere, Hollowmere,
## the troll den, the Ironway, the Moot...), every region it enters (the Greywood among its pines, Aldmere,
## the Stonehold), the main thread's stages, growth, the formations (a block bracing or advancing, a banner
## falling, the one the giant locks), the siege engines (one shooting at the giant) and what the giant
## grabs, the bosses (the Iron Regiment's battle in Fort Aldmere's bailey, the Troll Matriarch, Harrok at
## the Moot), the world events, the walk to the Stone Throne; then the campaign's end screen and the map
## screen, which the tour opens once the bot has finished (the bot never opens it). Plus one shot every
## --tour-every simulated seconds.
##
## A software renderer (Mesa llvmpipe under Xvfb) draws a 1280 x 720 frame of the world in about a second
## or more, so drawing every frame would play a campaign (about 2,000 simulated seconds) many times slower
## than real time. With --tour-render=shots (the default) the render loop is off except for the frames of
## each shot, so the bot plays at the speed of its headless runs (start it with --fixed-fps 60 and
## --deterministic-streaming, the headless runs' streaming and navigation rules); --tour-render=always draws
## every frame (as valley_tour.gd).
## While the bot plays the tour changes nothing in the game's state: it listens to Events, reads the bot's
## run and the giant, and keeps the mouse captured as a player's would be (the HUD otherwise asks for a
## click). No shot is taken while a screen is open - the bot counts a pausing screen held open 2 s of real
## time as an invariant failure, and a shot's frames take real time - so a shot that finds one waits, and a
## screen that opens during a shot's frames stops the frames (the shot is retried). When the bot's run is
## finished (the campaign's end, or a stop), the tour stops the Autopilot and the bot (process mode
## DISABLED, before the Autopilot's next tick would quit), shoots the end screen, closes it, shoots the
## giant at the throne and the map screen, then hands back to the Autopilot, which prints its
## AUTOPILOT_RESULT and quits.
##
## Placed (--tour-places=a,b,...). Scripted placements, for places the bot's route does not pass (the
## crown-first order never enters the Drowned Steps) and for retakes, as the M8 screenshot pass placed them:
## from --mode=world --new-game (no --scenario) it grows the giant (the debug grow, in open ground on the
## Kingsgate shelf), fast-travels (debug) to a waystone or shrine, puts the giant on a spot, turns the
## camera to the place, waits for the chunks around it and shoots. The places are PLACES below.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 --audio-driver Dummy \
##     --fixed-fps 60 -s res://tools/world_tour.gd -- --no-user-settings --save-dir=user://tour_saves \
##     --mode=world --new-game --scenario=world --bot-preset=peaceful "--bot-oaths=crown:breach,wood:slay" \
##     --bot-skill=novice --bot-seed=1 --bot-assist --autoplay=7200 --deterministic-streaming \
##     --tour-dir=/absolute/folder
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 --audio-driver Dummy \
##     --fixed-fps 60 -s res://tools/world_tour.gd -- --no-user-settings --save-dir=user://tour_place_saves \
##     --mode=world --new-game --deterministic-streaming --tour-places=drowned_steps --tour-dir=/absolute/folder
## tools/world_tour.sh runs either (the crown-first order assisted, w.order_crown:novice:1:assist, by default).
##
## Options (after --, besides the game's own): --tour-dir=PATH (default user://world_tour),
## --tour-every=S (a plain shot every S simulated seconds, default 120; 0 = none), --tour-max=N (at most N
## shots, default 180), --tour-render=shots|always, --tour-frames=N (frames drawn for each shot, the last
## one saved; default 2), --tour-places=LIST (placed mode).
## Shots are PNG files named <nnn>_<moment>.png. "TOUR_SHOT {json}" is printed for each (the file, the
## moment, the tick and simulated seconds, the giant's stage, region and place, the camera, the bot's
## objective, bot or placed) and the same lines go to <tour-dir>/shots.jsonl; "TOUR_PROGRESS" lines every
## 60 simulated seconds, "TOUR_SKIP" for a shot given up, "TOUR_END" last.

const MAIN_SCENE := "res://scenes/main.tscn"
const TICKS_PER_S := 60
## Scripts loaded by path: this script loads before the autoloads exist, so it must not name classes whose
## scripts use them.
const AUTOPILOT := "res://scripts/debug/autopilot.gd"
const BOTS := ["res://scripts/debug/world_bot.gd", "res://scripts/debug/valley_bot.gd"]
const VALLEY_BOT := "res://scripts/debug/valley_bot.gd"
const WORLD_INDEX := "res://scripts/world/world_index.gd"
const WORLD_LEVEL := "level.world"
const WORLD_MAIN := "quest.world_main"
const THRONE := "world.stonehold.stone_throne"
const CAMPAIGN_FLAG := "campaign.completed"
## The start: shots this many simulated seconds after play begins (the Kingsgate shelf's view).
const START_SHOTS_S := [2.5, 6.0, 11.0, 18.0]
## Formation states worth a shot (Formation._decide_state and its banner).
const FORMATION_STATES := ["braced", "advancing", "banner_fell", "broken", "routed"]
## Points of interest worth a second look (7 s after their discovery).
const SECOND_LOOK := ["kingsgate_shelf", "brannock", "millford", "fort_aldmere", "hollowmere", "troll_den",
	"ironway_top", "the_moot"]
## Telegraphs aimed at the giant: one shot per attack, at most this many in all, a minute apart.
const MAX_TELEGRAPH_SHOTS := 12
## A shot waiting for a screen to close is given up after this long (simulated seconds).
const WAIT_LIMIT_S := 20.0
const MAX_TRIES := 3

var _dir := "user://world_tour"
var _every_s := 120.0
var _max_shots := 180
var _render_always := false
var _frames := 2
var _places: PackedStringArray = []

var _queue: Array = []        # [{"tick", "name", "place", "tries", "due"}], due shots
var _counts := {}             # moment key -> shots planned
var _last_tick := {}          # moment key -> tick of its last plan
var _shots := 0
var _records: Array = []      # the shots.jsonl lines
var _busy := false
var _connected := false
var _play_start := -1         # the first tick of play (after the loading gate)
var _next_plain_tick := 0
var _next_progress_tick := 0
var _region := ""
var _main_stage := ""
var _lock_id := ""
var _ending := false
var _ending_started := false
var _disabled: Array = []     # [[node, its process mode]] stopped for the ending
var _vb_script: Script = null
var _t0_ms := 0
var _placed_started := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour-dir="):
			_dir = a.substr(11)
		elif a.begins_with("--tour-every="):
			_every_s = maxf(0.0, float(a.substr(13)))
		elif a.begins_with("--tour-max="):
			_max_shots = maxi(1, int(a.substr(11)))
		elif a.begins_with("--tour-render="):
			_render_always = a.substr(14) == "always"
		elif a.begins_with("--tour-frames="):
			_frames = clampi(int(a.substr(14)), 1, 30)
		elif a.begins_with("--tour-places="):
			_places = a.substr(14).split(",", false)
	DirAccess.make_dir_recursive_absolute(_dir)
	_t0_ms = Time.get_ticks_msec()
	_render(false)
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)
	change_scene_to_file(MAIN_SCENE)


# --------------------------------------------------------------------------- the game, read-only

func _node(path: String) -> Node:
	return root.get_node_or_null(path)


func _sim_tick() -> int:
	var sim := _node("/root/Sim")
	return int(sim.get("tick")) if sim != null else 0


func _player() -> Node3D:
	var session := _node("/root/GameSession")
	return session.call("player") as Node3D if session != null else null


func _stage() -> int:
	var session := _node("/root/GameSession")
	return int(session.call("current_stage")) if session != null else 0


func _stack() -> Node:
	var m := current_scene
	return m.get("screen_stack") as Node if m != null and "screen_stack" in m else null


func _level_ready() -> bool:
	var m := current_scene
	if m == null or not m.has_method("is_loading") or bool(m.call("is_loading")):
		return false
	return m.get("level") != null and _player() != null and m.get("hud") != null


func _any_screen_open() -> bool:
	for n in get_nodes_in_group("screen_stack"):
		if n.has_method("any_open") and bool(n.call("any_open")):
			return true
	return false


func _screen_open(screen_name: String) -> bool:
	for n in get_nodes_in_group("screen_stack"):
		if n.has_method("is_open") and bool(n.call("is_open", screen_name)):
			return true
	return false


## The bot's run (ValleyBot.run, a static of the Valley bot's script), or null outside a bot run.
func _bot_run() -> Object:
	if _vb_script == null and ResourceLoader.exists(VALLEY_BOT):
		_vb_script = load(VALLEY_BOT)
	return _vb_script.get("run") as Object if _vb_script != null else null


func _objective() -> String:
	var run := _bot_run()
	return str(run.get("obj_key")) if run != null else ""


func _index() -> Object:
	var s: Script = load(WORLD_INDEX)
	return s.call("for_level", WORLD_LEVEL) as Object if s != null else null


func _position_of(id: String) -> Vector3:
	var idx := _index()
	return idx.call("position_of", id) if idx != null else Vector3.INF


func _render(on: bool) -> void:
	RenderingServer.render_loop_enabled = on or _render_always


# --------------------------------------------------------------------------- the moments (bot mode)

func _connect() -> void:
	var ev := _node("/root/Events")
	if ev == null:
		return
	_connected = true
	if not _places.is_empty():
		return   # placed mode: the places shoot themselves
	ev.poi_discovered.connect(func(_t, poi_id):
		var short := str(poi_id).get_extension()
		_plan("poi_" + short, 1.5, 1)
		if short in SECOND_LOOK:
			_plan("poi_%s_b" % short, 7.0, 1))
	ev.region_changed.connect(func(_t, region_id, _prev):
		_region = str(region_id)
		var short := _region.get_extension()
		_plan("region_" + short, 3.0, 1)
		_plan("region_%s_b" % short, 25.0, 1))
	ev.quest_stage_changed.connect(func(_t, quest_id, stage_id):
		if str(quest_id) == WORLD_MAIN:
			_main_stage = str(stage_id)
			_plan("main_" + _main_stage, 1.5, 1))
	ev.growth_changed.connect(func(_t, entity_id, _old, new_stage):
		if str(entity_id) == "player":
			_plan("stage_%d" % int(new_stage), 2.5, 1)
			_plan("stage_%d_b" % int(new_stage), 9.0, 1))
	ev.formation_changed.connect(func(_t, formation_id, state):
		if str(state) in FORMATION_STATES:
			_plan("formation_" + str(state), 0.3 if str(state) == "braced" else 0.8, 2, 30.0))
	ev.siege_engine_fired.connect(func(_t, engine_id, _action, target_id):
		if str(target_id) == "player":
			_plan("siege_" + str(engine_id).get_extension(), 0.5, 2, 15.0))
	ev.grab_started.connect(func(_t, holder_id, target_id):
		if str(holder_id) == "player":
			_plan("grab", 0.5, 8, 20.0, str(target_id).get_extension()))
	ev.telegraph_started.connect(_on_telegraph)
	ev.boss_engaged.connect(func(_t, boss_id):
		var short := str(boss_id).get_extension()
		_plan("boss_" + short, 2.0, 1)
		_plan("boss_%s_b" % short, 15.0, 1)
		_plan("boss_%s_c" % short, 45.0, 1))
	ev.boss_phase_changed.connect(func(_t, boss_id, phase):
		_plan("boss_%s_phase%d" % [str(boss_id).get_extension(), int(phase)], 0.8, 1))
	ev.boss_defeated.connect(func(_t, boss_id):
		_plan("boss_%s_defeated" % str(boss_id).get_extension(), 1.0, 1))
	ev.world_event_started.connect(func(_t, event_id):
		var short := str(event_id).get_extension()
		_plan("event_" + short, 3.0, 1)
		_plan("event_%s_b" % short, 20.0, 1))
	# The campaign's end: the throne's claim completes the main quest and opens the end screen, which
	# pauses the game - and the bot, which runs while paused, closes any screen after 0.25 s of real time
	# before it notices the campaign done. So the bot and the Autopilot stop here, in the same tick.
	ev.flag_changed.connect(func(_t, flag_id, value):
		if str(flag_id) == CAMPAIGN_FLAG and bool(value) and not _ending:
			_begin_ending())


func _on_telegraph(_tick: int, _actor_id: String, action_id: String, target_id: String, _shape: String,
		_origin: Vector3, _yaw: float, _radius: float, _length: float, duration_s: float) -> void:
	if target_id != "player":
		return
	var key := "telegraph_" + action_id.get_extension()
	var now := _sim_tick()
	if _counts.has(key) or int(_counts.get("telegraphs", 0)) >= MAX_TELEGRAPH_SHOTS \
			or (_last_tick.has("telegraphs") and now - int(_last_tick.telegraphs) < 60 * TICKS_PER_S):
		return
	_counts["telegraphs"] = int(_counts.get("telegraphs", 0)) + 1
	_last_tick["telegraphs"] = now
	# Part-way through the windup: the decal half full, the attacker in its wind-up pose.
	_plan(key, duration_s * 0.55, 1)


## Schedules a shot `delay_s` simulated seconds from now, at most `max_count` times per key and no sooner
## than `gap_s` after the last one of that key. `suffix` is added to the file name only.
func _plan(key: String, delay_s: float, max_count: int, gap_s: float = 0.0, suffix := "") -> void:
	if _ending or _shots + _queue.size() >= _max_shots:
		return
	var now := _sim_tick()
	if int(_counts.get(key, 0)) >= max_count:
		return
	if _last_tick.has(key) and now - int(_last_tick[key]) < int(gap_s * TICKS_PER_S):
		return
	_counts[key] = int(_counts.get(key, 0)) + 1
	_last_tick[key] = now
	var shot_name := key if suffix == "" else "%s_%s" % [key, suffix]
	var due := now + int(round(delay_s * TICKS_PER_S))
	_queue.append({"tick": due, "name": shot_name, "tries": 0, "planned": now})


func _on_physics_frame() -> void:
	if not _connected:
		_connect()
	if not _level_ready():
		return
	var now := _sim_tick()
	if _play_start < 0:
		_play_start = now
		_next_plain_tick = now + int(_every_s * TICKS_PER_S) if _every_s > 0.0 else -1
		_next_progress_tick = now
		if _places.is_empty():
			for s in START_SHOTS_S:
				_queue.append({"tick": now + int(float(s) * TICKS_PER_S), "name": "shelf_view_%ds" % int(s),
					"tries": 0, "planned": now})
	if not _places.is_empty():
		if not _placed_started:
			_placed_started = true
			_run_places()
		return
	if now >= _next_progress_tick:
		_next_progress_tick = now + 60 * TICKS_PER_S
		print("TOUR_PROGRESS %s" % JSON.stringify({"tick": now, "sim_s": snappedf(now / 60.0, 0.1),
			"wall_s": snappedf((Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.1), "stage": _stage(),
			"region": _region, "objective": _objective(), "shots": _shots, "queued": _queue.size()}))
	if _ending:
		return
	var run := _bot_run()
	if run != null and bool(run.get("finished")):
		_begin_ending()
		return
	if _next_plain_tick > 0 and now >= _next_plain_tick:
		_next_plain_tick = now + int(_every_s * TICKS_PER_S)
		_queue.append({"tick": now, "name": "t%04d" % int((now - _play_start) / TICKS_PER_S), "tries": 0,
			"planned": now})
	if now % 15 == 0:
		_watch_lock_and_throne(now)


## The formation the giant locks (the camera frames its group) and the last steps to the Stone Throne.
func _watch_lock_and_throne(now: int) -> void:
	var p := _player()
	if p == null:
		return
	var rig: Object = p.get("camera_rig")
	var group: Object = rig.get("p30_lock_group") if rig != null else null
	var id := ""
	if group != null and not bool(group.get("dissolved")):
		id = str(group.get("id"))
	if id != "" and id != _lock_id:
		_plan("lock_" + id.get_extension(), 0.6, 1)
		_plan("lock_%s_b" % id.get_extension(), 5.0, 1)
	_lock_id = id
	if _main_stage == "throne":
		var throne := _position_of(THRONE)
		if throne.is_finite():
			var d := Vector2(p.global_position.x - throne.x, p.global_position.z - throne.z).length()
			if d < 40.0:
				_plan("throne_near", 0.0, 6, 3.0)


# --------------------------------------------------------------------------- shooting

func _on_process_frame() -> void:
	# A player's mouse is captured while they play (the HUD otherwise asks for a click). Tool runs never
	# capture it themselves.
	if not paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _busy:
		return
	if _ending:
		if not _ending_started:
			_ending_started = true
			_run_ending()
		return
	if _shots >= _max_shots or not _places.is_empty():
		return
	var now := _sim_tick()
	for i in _queue.size():
		var e: Dictionary = _queue[i]
		if int(e.tick) > now:
			continue
		if _any_screen_open():
			# Wait for the screen to close (the bot closes them); give up after WAIT_LIMIT_S.
			if now - int(e.tick) > int(WAIT_LIMIT_S * TICKS_PER_S):
				_queue.remove_at(i)
				print("TOUR_SKIP %s (a screen stayed open)" % e.name)
			return
		_queue.remove_at(i)
		_shoot(e)
		return


## Draws `_frames` frames (the render loop on for them alone) and saves the last. A screen opening meanwhile
## stops the frames: the shot goes back in the queue (MAX_TRIES at most).
func _shoot(e: Dictionary) -> void:
	_busy = true
	var t0 := Time.get_ticks_msec()
	_render(true)
	for i in _frames:
		await RenderingServer.frame_post_draw
		if not _ending and _places.is_empty() and _any_screen_open():
			_render(false)
			_busy = false
			e.tries = int(e.tries) + 1
			if int(e.tries) < MAX_TRIES:
				e.tick = _sim_tick() + 2 * TICKS_PER_S
				_queue.append(e)
			else:
				print("TOUR_SKIP %s (screens during its frames)" % e.name)
			return
	var img := root.get_texture().get_image()
	_render(false)
	_save(img, str(e.name), Time.get_ticks_msec() - t0)
	_busy = false


func _save(img: Image, shot_name: String, render_ms: int) -> void:
	_shots += 1
	var path := _dir.path_join("%03d_%s.png" % [_shots, shot_name.validate_filename()])
	img.save_png(path)
	var p := _player()
	var rig: Object = p.get("camera_rig") if p != null else null
	var rec := {"file": path.get_file(), "moment": shot_name, "origin": "placed" if not _places.is_empty() else "bot",
		"tick": _sim_tick(), "sim_s": snappedf(_sim_tick() / 60.0, 0.01), "stage": _stage(), "region": _region,
		"objective": _objective(), "render_ms": render_ms,
		"wall_s": snappedf((Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.1)}
	if p != null:
		var pos := p.global_position
		rec["pos"] = [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)]
		var idx := _index()
		if idx != null:
			rec["region"] = str(idx.call("region_at", pos))
	if rig != null:
		rec["camera"] = {"yaw_deg": snappedf(rad_to_deg(float(rig.get("yaw"))), 0.1),
			"pitch_deg": snappedf(rad_to_deg(float(rig.get("pitch"))), 0.1),
			"distance_m": snappedf(float(rig.get("current_distance")), 0.01)}
	var line := JSON.stringify(rec)
	print("TOUR_SHOT " + line)
	_records.append(line)
	var f := FileAccess.open(_dir.path_join("shots.jsonl"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_records) + "\n")
		f.close()


## Waits until the shot in progress (if any) is saved, then shoots `shot_name` now.
func _shoot_now(shot_name: String) -> void:
	while _busy:
		await process_frame
	await _shoot({"tick": _sim_tick(), "name": shot_name, "tries": MAX_TRIES})


func _frames_wait(n: int) -> void:
	for i in n:
		await process_frame


## Waits `s` seconds of simulation (at most 6 x that in frames, so a paused tree does not hold it forever).
func _sim_wait(s: float) -> void:
	var start := _sim_tick()
	var guard := 0
	while _sim_tick() - start < int(s * TICKS_PER_S) and guard < int(s * TICKS_PER_S) * 6 + 60:
		await process_frame
		guard += 1


# --------------------------------------------------------------------------- the ending (bot mode)

## The bot's run is finished: stop the Autopilot and the bot before the Autopilot's next tick would quit.
func _begin_ending() -> void:
	_ending = true
	for n in root.find_children("*", "", true, false):
		var script: Script = n.get_script()
		if script != null and (script.resource_path == AUTOPILOT or script.resource_path in BOTS):
			_disabled.append([n, n.process_mode])
			n.process_mode = Node.PROCESS_MODE_DISABLED
	# The run as it stands (the Autopilot's AUTOPILOT_RESULT follows the hand-back; this line is there
	# should the hand-back fail).
	var run := _bot_run()
	var m: Object = run.get("metrics") if run != null else null
	var ws := _node("/root/WorldState")
	print("TOUR_ENDING %s" % JSON.stringify({"tick": _sim_tick(), "sim_s": snappedf(_sim_tick() / 60.0, 0.01),
		"finished": bool(run.get("finished")) if run != null else false,
		"reason": str(run.get("finish_reason")) if run != null else "",
		"campaign_completed": _campaign_completed(), "stage": _stage(), "objective": _objective(),
		"deaths": (m.get("deaths") as Array).size() if m != null else -1,
		"throne": bool(ws.call("get_flag", "world.throne.claimed", false)) if ws != null else false,
		"wall_s": snappedf((Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.1)}))


func _run_ending() -> void:
	# The campaign's end screen opens with the throne's claim (it pauses the game).
	for i in 30:
		if _screen_open("end"):
			break
		await process_frame
	if _screen_open("end"):
		await _frames_wait(4)
		await _shoot_now("end_screen")
		var stack := _stack()
		var top: Object = stack.call("top") if stack != null else null
		if top != null and top.has_method("close"):
			top.call("close")
	# A few frames only (with --fixed-fps a frame is a tick): the run's simulated time stays the bot's.
	await _frames_wait(6)
	await _shoot_now("throne_claimed" if _campaign_completed() else "where_it_stopped")
	await _map_shots()
	_finish()


func _campaign_completed() -> bool:
	var ws := _node("/root/WorldState")
	return ws != null and bool(ws.call("get_flag", "campaign.completed", false))


## The map screen with the world as the run left it (opened by the tour: the bot never opens it). It
## opens centred on the giant; zoomed out (set_zoom(0), which keeps the view inside the world) it shows
## the whole world. Then `select_id`'s entry is selected (its panel): the Moot by default, where the
## campaign ends, or the first of the fallbacks the map knows.
func _map_shots(select_id := "poi.the_moot") -> void:
	var stack := _stack()
	if stack == null:
		return
	var m: Object = stack.call("open", "map", {})
	if m == null:
		print("TOUR_SKIP map (the map screen did not open)")
		return
	await _frames_wait(8)
	if m.has_method("set_zoom"):
		m.call("set_zoom", 0)
		await _frames_wait(4)
	await _shoot_now("map_world")
	for id in [select_id, "poi.the_moot", "world.cp.moot_foot", "world.shrine.stones"]:
		if m.has_method("select") and bool(m.call("select", id)):
			await _frames_wait(4)
			await _shoot_now("map_" + str(id).get_extension())
			break
	if is_instance_valid(m) and m.has_method("close"):
		m.call("close")
	await _frames_wait(4)


## Hands back to the Autopilot: it prints its AUTOPILOT_RESULT and quits on its next tick (the bot's run
## is finished). Without one (a run that stopped otherwise) the tour quits itself.
func _finish() -> void:
	print("TOUR_END %s" % JSON.stringify({"shots": _shots, "tick": _sim_tick(), "sim_s": snappedf(_sim_tick() / 60.0, 0.01),
		"wall_s": snappedf((Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.1), "dir": _dir}))
	var restored := 0
	for pair in _disabled:
		var n: Node = pair[0]
		if is_instance_valid(n):
			n.process_mode = pair[1]
			restored += 1
	_disabled.clear()
	if restored == 0:
		quit()
		return
	# The bot notices the campaign's end on its next tick (stopped at the flag, it has not yet) and the
	# Autopilot finishes on the tick after; a guard quits anyway if it has not within 600 frames.
	await _frames_wait(600)
	print("TOUR_SKIP the Autopilot's result (it did not finish within 600 frames)")
	quit()


# --------------------------------------------------------------------------- placed mode

## The scripted places (--tour-places): name -> [stage, steps]. A step is
## {"travel": checkpoint} | {"at": [x, z]} | {"aim": [x, y, z], "offset": deg, "pitch": deg, "dist": m} |
## {"shot": name} | {"wait": s} | {"map": entry to select}. The giant is grown to the stage first (in
## open ground on the shelf; a stage of 0 or one the giant has keeps it).
const PLACES := {
	"drowned_steps": [5, [
		{"travel": "world.shrine.steps"},
		{"at": [-188.0, 132.0]}, {"aim": [-120.0, 4.0, 20.0], "offset": 16.0, "pitch": -16.0, "dist": 26.0},
		{"wait": 3.0}, {"shot": "drowned_steps_terraces"},
		{"aim": [0.0, 4.0, -40.0], "offset": -14.0, "pitch": -12.0, "dist": 26.0}, {"wait": 2.0},
		{"shot": "drowned_steps_mere"},
		{"travel": "world.cp.mere_south"},
		{"at": [60.0, 150.0]}, {"aim": [22.0, 4.0, 40.0], "offset": 14.0, "pitch": -14.0, "dist": 26.0},
		{"wait": 3.0}, {"shot": "drowned_steps_vault"},
		{"travel": "world.cp.bell_tower"},
		{"at": [-172.0, -196.0]}, {"aim": [-200.0, 14.0, -240.0], "offset": 14.0, "pitch": -10.0, "dist": 24.0},
		{"wait": 3.0}, {"shot": "drowned_steps_bell_tower"},
	]],
	# The map screen zoomed out to the whole world, then the Moot selected. To show what a bot run
	# discovered, continue its save: tools/world_tour.sh --places=map -- --continue --save-dir=<its folder>.
	"map": [0, [{"map": "poi.the_moot"}]],
	"greywood": [5, [
		{"travel": "world.cp.hollowmere"},
		{"at": [-605.0, 10.0]}, {"aim": [-645.0, 18.0, -45.0], "offset": 14.0, "pitch": -12.0, "dist": 26.0},
		{"wait": 3.0}, {"shot": "greywood_hollowmere"},
	]],
	# The view down from the shelf where the bot's route takes it six seconds in (its shelf_view_6s shot,
	# camera yaw -31.6, pitch -18), without the tutorial tip a new game shows there.
	"shelf": [3, [
		{"travel": "world.cp.kingsgate_shelf"},
		{"at": [-299.0, 870.0]}, {"aim": [-194.0, 10.0, 700.0], "offset": 0.0, "pitch": -18.0, "dist": 12.2},
		{"wait": 3.0}, {"shot": "shelf_vista"},
	]],
	"brannock": [4, [
		{"travel": "world.cp.brannock"},
		{"at": [75.0, 520.0]}, {"aim": [55.0, 12.0, 450.0], "offset": 14.0, "pitch": -12.0, "dist": 22.0},
		{"wait": 3.0}, {"shot": "brannock"},
	]],
	"aldmere_gate": [4, [
		{"travel": "world.cp.fort_gate"},
		{"aim": [650.0, 60.0, -170.0], "offset": 14.0, "pitch": -10.0, "dist": 22.0},
		{"wait": 3.0}, {"shot": "aldmere_gate"},
	]],
	"moot": [6, [
		{"travel": "world.cp.moot_foot"},
		{"aim": [0.0, 95.0, -770.0], "offset": 16.0, "pitch": -10.0, "dist": 30.0},
		{"wait": 3.0}, {"shot": "moot"},
		{"at": [0.0, -750.0]}, {"aim": [0.0, 96.0, -790.0], "offset": 14.0, "pitch": -12.0, "dist": 22.0},
		{"wait": 3.0}, {"shot": "stone_throne"},
	]],
}
## Open ground on the Kingsgate shelf where the debug grow finds room (the M8 pass's spots).
const GROW_SPOTS := [Vector2(-300, 905), Vector2(-280, 700), Vector2(-200, 820)]


func _run_places() -> void:
	await _sim_wait(1.0)
	_hide_tips()
	for place in _places:
		if not PLACES.has(place):
			print("TOUR_SKIP %s (no such place: %s)" % [place, ", ".join(PLACES.keys())])
			continue
		var spec: Array = PLACES[place]
		print("TOUR_PLACE %s (stage %d)" % [place, int(spec[0])])
		await _grow_to(int(spec[0]))
		for step: Dictionary in spec[1]:
			if step.has("travel"):
				if not await _travel(str(step.travel)):
					break
			elif step.has("at"):
				await _place_at(float(step.at[0]), float(step.at[1]))
			elif step.has("aim"):
				var a: Array = step.aim
				_aim(Vector3(float(a[0]), float(a[1]), float(a[2])), float(step.get("offset", 0.0)),
					float(step.get("pitch", -14.0)), float(step.get("dist", -1.0)))
			elif step.has("wait"):
				await _settle()
				await _sim_wait(float(step.wait))
				await _wait_messages_clear(8.0)
			elif step.has("shot"):
				await _shoot_now(str(step.shot))
			elif step.has("map"):
				await _map_shots(str(step.map))
	print("TOUR_END %s" % JSON.stringify({"shots": _shots, "dir": _dir}))
	quit()


## Marks every tutorial prompt seen and dismisses the one showing (a player who has read them).
func _hide_tips() -> void:
	var data := _node("/root/GameData")
	var ws := _node("/root/WorldState")
	var quests := _node("/root/Quests")
	var tutorial_script: Script = load("res://scripts/quests/tutorial_director.gd") if \
		ResourceLoader.exists("res://scripts/quests/tutorial_director.gd") else null
	if data == null or ws == null or tutorial_script == null:
		return
	for rec: Dictionary in data.call("records_of_type", "tutorial_prompt"):
		ws.call("try_set_flag", tutorial_script.call("seen_flag", str(rec.get("id", ""))), true)
	var tut: Object = quests.get("tutorial") if quests != null else null
	if tut != null and not (tut.get("current") as Dictionary).is_empty():
		tut.call("dismiss", "timeout", _sim_tick())


func _grow_to(stage: int) -> void:
	var p := _player()
	if p == null or _stage() >= stage:
		return
	for target in range(_stage() + 1, stage + 1):
		var grown := false
		for spot: Vector2 in GROW_SPOTS:
			await _place_at(spot.x, spot.y)
			await _sim_wait(0.5)
			var r: Dictionary = _player().get("growth").call("debug_set_stage", target)
			if bool(r.get("ok", false)):
				grown = true
				await _sim_wait(0.5)
				break
		if not grown:
			print("TOUR_SKIP grow to %d (no room at the grow spots)" % target)
			return


func _travel(checkpoint_id: String) -> bool:
	var session := _node("/root/GameSession")
	var r: Dictionary = session.call("travel_to", WORLD_LEVEL, checkpoint_id, "debug")
	if not bool(r.get("ok", false)):
		print("TOUR_SKIP travel to %s (%s)" % [checkpoint_id, str(r)])
		return false
	await _frames_wait(5)
	for i in 6000:
		if _level_ready():
			break
		await process_frame
	await _frames_wait(5)
	_hide_tips()
	await _settle()
	return true


func _place_at(x: float, z: float) -> void:
	var p := _player()
	var lv: Node = current_scene.get("level") if current_scene != null else null
	var y := p.global_position.y
	if lv != null and lv.has_method("height_at"):
		var h: float = lv.call("height_at", Vector3(x, 0, z))
		if is_finite(h):
			y = h
	p.global_position = Vector3(x, y + 0.3, z)
	p.set("velocity", Vector3.ZERO)
	await _frames_wait(3)


## Turns the giant toward `target` and the camera `offset_deg` to the side of it (positive turns the view
## left, so the target shows right of the giant), pitch in degrees, arm length (or -1 to keep).
func _aim(target: Vector3, offset_deg: float, pitch_deg: float, dist: float) -> void:
	var p := _player()
	var d := target - p.global_position
	var yaw := atan2(-d.x, -d.z)
	p.set("facing_yaw", yaw)
	p.rotation.y = yaw
	var rig: Object = p.get("camera_rig")
	rig.set("yaw", wrapf(yaw + deg_to_rad(offset_deg), -PI, PI))
	rig.set("pitch", deg_to_rad(pitch_deg))
	if dist > 0.0:
		rig.set("desired_distance", dist)
		rig.set("current_distance", dist)


## Waits until the ring of chunks around the giant is ready and the streamer idle (helping it along).
func _settle(max_frames := 900) -> void:
	var lv: Node = current_scene.get("level") if current_scene != null else null
	var st: Object = lv.get("streamer") if lv != null and "streamer" in lv else null
	if st == null:
		await _sim_wait(1.0)
		return
	for i in max_frames:
		var p := _player()
		if p == null:
			break
		var stats: Dictionary = st.call("stats")
		if bool(st.call("ring_ready", p.global_position)) and int(stats.get("queue", 0)) == 0 \
				and str(stats.get("loading", "")) == "":
			break
		st.call("load_ring_slice", p.global_position)
		await process_frame
	await _sim_wait(1.0)


## Waits (simulated time) until the HUD's message line is empty, at most max_s.
func _wait_messages_clear(max_s: float) -> void:
	var hud: Object = current_scene.get("hud") if current_scene != null else null
	var t := 0.0
	while hud != null and hud.has_method("message_texts") and t < max_s:
		var texts: Variant = hud.call("message_texts")
		if texts.is_empty():
			break
		await _sim_wait(0.5)
		t += 0.5
