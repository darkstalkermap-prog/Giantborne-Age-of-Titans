extends SceneTree
## The townsfolk's, the riders' and the rival giants' rendered checks (P62; plan M11 §2.10, §2.12, §3.15), run in a
## child process under Xvfb (the headless runner renders nothing), with the gl_compatibility renderer at the `low`
## preset:
##
##   xvfb-run -a -s "-screen 0 640x480x24" godot --path . --rendering-driver opengl3 --resolution 640x480 \
##     --audio-driver Dummy --fixed-fps 60 -s res://tests/support/townsfolk_probe.gd -- --no-user-settings --probe=<mode>
##
## Every mode prints one line, "TOWNSFOLK_PROBE {json}", then quits.
##   town         a stage-1 giant (its own camera, the game camera) on a floor under a sun; ahead of him a town's
##                people - seven villagers, the seven named talkers, Corvane - and two riders: the draw calls a rider
##                adds alone (the horse, the rider, the lance), a named character alone, the whole view; for every
##                skinned person whether its arms hang (no bind pose: each hand under its shoulder), its clip, its
##                feet on the ground; the riders' hooves on the ground; the people's CPU a frame (the rigs' and the
##                renderers' process time); then the rival giant and Harrok beside him: their draw calls.
##   settlements  scenes/world/world.tscn with its encounter director, the giant (stage 3) set down at each of the six
##                settlements' greens (Millford, Brannock, Hollowmere, Fort Aldmere, Skarn, Harrok's Hall) and then
##                at the Moot test level's ring: the encounters spawn, the stage-3 camera turns through four
##                directions; per place the most draw calls, the people drawn (skinned, crowd, far) and the people's
##                CPU a frame.
## Loaded at run time, untyped: a -s script compiles before the autoloads are registered.

const GIANT := "res://scenes/player/giant.tscn"
const WORLD := "res://scenes/world/world.tscn"
const MOOT := "res://scenes/test/moot_test.tscn"
const SETTLE := 8
## [scene, record, id, position, faction]
const TOWN := [
	["res://scenes/npcs/elder.tscn", "npc.edda", "probe.edda", Vector3(-5.0, 0.05, 0.5), "brannock"],
	["res://scenes/npcs/elder.tscn", "npc.reeve_tamsin", "probe.tamsin", Vector3(-3.5, 0.05, 0.0), "millford"],
	["res://scenes/npcs/elder.tscn", "npc.sedge", "probe.sedge", Vector3(-2.0, 0.05, 0.5), "woodfolk"],
	["res://scenes/npcs/elder.tscn", "npc.ferrywoman", "probe.ferrywoman", Vector3(-0.5, 0.05, 0.0), "village"],
	["res://scenes/npcs/elder.tscn", "npc.herald", "probe.herald", Vector3(1.0, 0.05, 0.5), "aldmere"],
	["res://scenes/npcs/elder.tscn", "npc.toll_captain", "probe.toll_captain", Vector3(2.5, 0.05, 0.0), "toll_riders"],
	["res://scenes/npcs/elder.tscn", "npc.deserter", "probe.deserter", Vector3(4.0, 0.05, 0.5), "aldmere"],
	["res://scenes/enemies/corvane.tscn", "enemy.corvane", "probe.corvane", Vector3(5.5, 0.05, 0.0), "aldmere"],
]
## The six settlements' greens (world_draw_probe.gd's viewpoints) and the stage-3 camera.
const VIEWS := {"millford": [-380, 618], "brannock": [60, 565], "hollowmere": [-610, 22], "fort_aldmere": [650, -62],
	"skarn": [440, -640], "harroks_hall": [-560, -690]}
const PIVOT_M := 7.25
const ARM_M := 12.0
const PITCH_DEG := -18.0

var _root3d: Node3D
var _giant: Node3D
var _out := {}
var _mode := "town"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			_mode = a.get_slice("=", 1)
	var settings := get_root().get_node_or_null("Settings")
	if settings != null:
		settings.set("graphics_override", "low")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _cls(n: String) -> Object:
	for c in ProjectSettings.get_global_class_list():
		if str(c["class"]) == n:
			return load(str(c.path))
	return null


static func _calls() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _run() -> void:
	await _frames(2)
	if _mode == "settlements":
		await _settlements()
	else:
		await _town()
	print("TOWNSFOLK_PROBE " + JSON.stringify(_out))
	quit(0)


func _stage() -> void:
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.55, 0.68)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.environment.ambient_light_energy = 0.6
	_root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = false
	_root3d.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	floor_mesh.mesh = plane
	_root3d.add_child(floor_mesh)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	_root3d.add_child(body)
	_giant = (load(GIANT) as PackedScene).instantiate() as Node3D
	_giant.position = Vector3(0, 0.05, 9)
	_root3d.add_child(_giant)


func _spawn(scene: String, record: String, id: String, pos: Vector3, yaw: float, faction := "") -> Node3D:
	var e := (load(scene) as PackedScene).instantiate() as Node3D
	e.set("entity_id", id)
	e.set("ai_enabled", false)
	if faction != "":
		e.set("faction", faction)
	(e.get_node("CombatEntity") as Node).set("definition_id", record)
	e.position = pos
	e.rotation.y = yaw
	_root3d.add_child(e)
	return e


func _town() -> void:
	_stage()
	await _frames(SETTLE)
	var cam: Camera3D = (_giant.get("camera_rig") as Node).get("camera")
	cam.current = true
	_giant.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(SETTLE)
	var base := _calls()
	var rider := _spawn("res://scenes/enemies/cavalry.tscn", "enemy.cavalry", "probe.rider_1", Vector3(-3.0, 0.05, -3.0), PI * 0.5, "aldmere")
	await _frames(SETTLE)
	_out["rider_skinned"] = bool(rider.get_node("Visual").get("skinned"))
	_out["rider_calls"] = _calls() - base
	base = _calls()
	var edda := _spawn(TOWN[0][0], TOWN[0][1], TOWN[0][2], TOWN[0][3], PI, TOWN[0][4])
	await _frames(SETTLE)
	_out["named_calls"] = _calls() - base
	var people: Array = [edda]
	for i in range(1, TOWN.size()):
		people.append(_spawn(TOWN[i][0], TOWN[i][1], TOWN[i][2], TOWN[i][3], PI, TOWN[i][4]))
	for i in 7:
		people.append(_spawn("res://scenes/npcs/villager.tscn", "npc.villager", "probe.villager_%d" % i,
			Vector3(-6.0 + i * 2.0, 0.05, -4.0 - (i % 2) * 1.5), PI + (i - 3) * 0.25, "village"))
	var rider2 := _spawn("res://scenes/enemies/cavalry.tscn", "enemy.cavalry", "probe.rider_2", Vector3(4.5, 0.05, -8.0), -PI * 0.5, "aldmere")
	await _frames(SETTLE * 2)
	_out["town_calls"] = _calls()
	# every skinned person: its arms hang (each hand under its shoulder), a clip plays, its feet on the ground
	var posed := 0
	var bad: Array = []
	var skinned := 0
	for p: Node3D in people:
		var rig := p.get_node("Visual")
		if not bool(rig.call("skinned")):
			continue
		skinned += 1
		var m: Node3D = rig.call("model")
		var sk: Skeleton3D = m.call("skeleton")
		var ok := true
		for side in ["l", "r"]:
			var sh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("upperarm_" + side)).origin
			var ha := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_" + side)).origin
			if ha.y > sh.y - 0.3:
				ok = false
		var foot := minf((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot_l")).origin).y,
			(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot_r")).origin).y)
		if foot > 0.25 or foot < -0.05:
			ok = false
		if str((m.call("player") as AnimationPlayer).current_animation) == "":
			ok = false
		if ok:
			posed += 1
		else:
			bad.append(str(p.get("entity_id")))
	_out["skinned"] = skinned
	_out["posed"] = posed
	_out["bad"] = bad
	# the riders' hooves on the ground
	var hoof_worst := 0.0
	for r: Node3D in [rider, rider2]:
		var vis := r.get_node("Visual")
		for leg in ["fore_l", "fore_r", "hind_l", "hind_r"]:
			if not bool(((vis.call("hooves") as Dictionary)[leg] as Array)[1]):
				continue   # (a hoof stepping back to its place after a shove)
			var s: Vector3 = vis.call("posed_sole", leg)
			hoof_worst = maxf(hoof_worst, absf(s.y - r.global_position.y))
	_out["hoof_height_worst"] = hoof_worst
	_out["people_cpu_ms"] = await _people_cpu()
	# the rival giant and Harrok beside the giant
	base = _calls()
	var rival := _spawn("res://scenes/enemies/rival_giant.tscn", "enemy.rival_giant", "probe.rival", Vector3(-14, 0.05, -10), PI, "")
	await _frames(SETTLE)
	_out["rival_calls"] = _calls() - base
	base = _calls()
	var harrok := _spawn("res://scenes/enemies/harrok.tscn", "enemy.harrok", "probe.harrok", Vector3(16, 0.05, -14), PI, "")
	await _frames(SETTLE)
	_out["harrok_calls"] = _calls() - base
	_out["rival_look"] = str(rival.get_node("Visual").get("own_look"))
	_out["harrok_look"] = str(harrok.get_node("Visual").get("own_look"))
	_out["adapter"] = RenderingServer.get_video_adapter_name()


## The people's CPU a frame (ms): every PersonRig's, SkinnedQuadrupedRig's and crowd renderer's _process, timed.
func _people_cpu() -> float:
	var us := 0
	var n := 30
	for k in n:
		await process_frame
		for rig in _people_rigs():
			var t := Time.get_ticks_usec()
			rig.call("_process", 1.0 / 60.0)
			us += Time.get_ticks_usec() - t
		var t2 := Time.get_ticks_usec()
		for r in get_nodes_in_group("crowd_renderers"):
			r.call("refresh")
		var loners: Variant = _cls("PersonRig").call("loner_renderer")
		if loners != null:
			(loners as Node).call("refresh")
		us += Time.get_ticks_usec() - t2
	return float(us) / float(n) / 1000.0


func _people_rigs() -> Array:
	var out: Array = []
	out.append_array(_cls("PersonRig").call("rigs"))
	out.append_array(get_nodes_in_group("skinned_quadruped_rigs"))
	return out


func _settlements() -> void:
	var world := (load(WORLD) as PackedScene).instantiate() as Node3D
	get_root().add_child(world)
	var cam := Camera3D.new()
	cam.far = 2400.0
	cam.fov = 75.0
	world.add_child(cam)
	cam.make_current()
	await _frames(4)
	var player := world.get_node_or_null("Player") as Node3D
	var streamer: Object = world.get("streamer")
	var views := {}
	for view: String in VIEWS:
		var xz: Array = VIEWS[view]
		var at := Vector3(float(xz[0]), 0.0, float(xz[1]))
		if streamer != null:
			var guard := 0
			while not bool(streamer.call("ring_ready", at)) and guard < 4000:
				streamer.call("load_ring_slice", at)
				guard += 1
		var ground := float(world.call("height_at", at))
		at.y = ground if is_finite(ground) else 0.0
		player.global_position = at + Vector3.UP * 0.1
		await _frames(150)   # the encounters spawn and settle
		views[view] = await _measure(cam, player, at)
	world.queue_free()
	await _frames(4)
	var moot := (load(MOOT) as PackedScene).instantiate() as Node3D
	get_root().add_child(moot)
	var mcam := Camera3D.new()
	mcam.far = 2400.0
	mcam.fov = 75.0
	moot.add_child(mcam)
	mcam.make_current()
	var mp := moot.get_node_or_null("Player") as Node3D
	await _frames(90)
	views["moot_test"] = await _measure(mcam, mp, mp.global_position)
	_out["views"] = views
	var worst := 0
	for v: String in views:
		worst = maxi(worst, int((views[v] as Dictionary).calls))
	_out["max_calls"] = worst
	_out["adapter"] = RenderingServer.get_video_adapter_name()


## The most draw calls through four directions of the stage-3 camera at `at`, the people drawn, their CPU.
func _measure(cam: Camera3D, player: Node3D, at: Vector3) -> Dictionary:
	var best := 0
	for k in 4:
		var yaw := TAU * float(k) / 4.0
		var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), yaw, 0.0))
		cam.global_transform = Transform3D(basis, at + Vector3.UP * PIVOT_M + basis.z * ARM_M)
		await _frames(4)
		best = maxi(best, _calls())
	var levels := {"skinned": 0, "crowd": 0, "far": 0, "other": 0}
	for r in _cls("PersonRig").call("rigs"):
		var l := str(r.call("level_name"))
		levels[l if levels.has(l) else "other"] = int(levels.get(l if levels.has(l) else "other", 0)) + 1
	var horses := get_nodes_in_group("skinned_quadruped_rigs").size()
	return {"calls": best, "people": levels, "horses": horses, "people_cpu_ms": await _people_cpu()}
