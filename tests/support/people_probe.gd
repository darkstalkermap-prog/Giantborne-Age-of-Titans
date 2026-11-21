extends SceneTree
## The people's rendered checks (P60; plan M11 §2.9, §3.13), run in a child process under Xvfb by
## tests/slow/test_people_render.gd and tests/gate/test_people_readability.gd (the headless runner renders
## nothing), with the gl_compatibility renderer:
##
##   xvfb-run -a -s "-screen 0 640x480x24" godot --path . --resolution 640x480 --audio-driver Dummy \
##     -s res://tests/support/people_probe.gd -- --no-user-settings --probe=<mode>
##
## Every mode stands a stage-1 giant (its own CameraRig's camera, the game camera; the people stand ahead of him and a
## little to his right, clear of his body) on a floor under a sun and
## prints one line, "PEOPLE_PROBE {json}", then quits.
##   render       a skinned soldier alone: the draw calls it adds (the body, the sword: plan §2.12's at most 3);
##                then forty soldiers in a block of 8 x 5 a few metres ahead with the cap at 0 (all crowd
##                instances) and one of them flashed: the pixels that changed and their box (the flash reaches one
##                crowd instance, and only it); the block moved to about 30 m: the draw calls and primitives of the
##                forty as a crowd, then with the sixteen nearest
##                skinned (the cap at 16): draw calls, primitives and the people's CPU a frame (the rigs' and
##                the renderers' process time, natively: in all, and split skinned, instanced, renderers);
##   readability  for every telegraphed attack of every role, a person 4 m before the giant: the share of its
##                screen box that changed between its idle and the end of its wind-up (plan §2.9: at least 1.5 %).
##   creatures    (P64) the same for the brutes, the bosses and the wolves, skinned (BruteRig, SkinnedWolfRig), each
##                standing far enough ahead to be seen whole (1.4 x its height, at least 4 m).
## Loaded at run time, untyped: a -s script compiles before the autoloads are registered.

const GIANT := "res://scenes/player/giant.tscn"
const SETTLE := 6
## [scene, record, telegraphed actions] (the formation braces are added to the pikeman's and shieldman's library)
const ROLES := [
	["res://scenes/enemies/soldier.tscn", "enemy.soldier", ["ability.soldier_chop", "ability.soldier_brace"]],
	["res://scenes/enemies/pikeman.tscn", "enemy.pikeman", ["ability.pike_thrust", "ability.formation_brace_pike"]],
	["res://scenes/enemies/shieldman.tscn", "enemy.shieldman", ["ability.formation_brace_shield"]],
	["res://scenes/enemies/shieldman.tscn", "enemy.iron_guard", ["ability.formation_brace_shield"]],
	["res://scenes/enemies/archer.tscn", "enemy.archer", ["ability.archer_shot"]],
	["res://scenes/enemies/mage.tscn", "enemy.mage", ["ability.mage_slow_bolt", "ability.mage_barrier"]],
]

## P64: [scene, record, telegraphed actions] of the creatures (mode "creatures").
const CREATURES := [
	["res://scenes/enemies/ogre.tscn", "enemy.ogre", ["ability.ogre_smash", "ability.ogre_sweep"]],
	["res://scenes/enemies/troll.tscn", "enemy.troll", ["ability.troll_stomp", "ability.troll_club"]],
	["res://scenes/enemies/troll_whelp.tscn", "enemy.troll_whelp", ["ability.troll_whelp_swipe"]],
	["res://scenes/enemies/ogre_king.tscn", "enemy.ogre_king", ["ability.boss_combo_1", "ability.boss_combo_2",
		"ability.boss_slam", "ability.boss_charge", "ability.boss_phase_roar"]],
	["res://scenes/enemies/troll_matriarch.tscn", "enemy.troll_matriarch", ["ability.matriarch_sweep",
		"ability.matriarch_stomp", "ability.matriarch_frenzy_1", "ability.matriarch_roar"]],   # (the whelp throw needs a whelp)
	["res://scenes/enemies/wolf.tscn", "enemy.wolf", ["ability.wolf_lunge"]],
	["res://scenes/enemies/dire_wolf.tscn", "enemy.dire_wolf", ["ability.dire_wolf_lunge"]],
]

var _root3d: Node3D
var _giant: Node3D
var _out := {}
var _mode := "render"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			_mode = a.get_slice("=", 1)
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
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	_root3d.add_child(floor_mesh)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	_root3d.add_child(body)
	_giant = (load(GIANT) as PackedScene).instantiate() as Node3D
	_giant.position = Vector3(0, 0.05, 6)
	_root3d.add_child(_giant)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _cls(name: String) -> Object:
	for c in ProjectSettings.get_global_class_list():
		if str(c["class"]) == name:
			return load(str(c.path))
	return null


func _run() -> void:
	await _frames(SETTLE)
	var cam: Camera3D = (_giant.get("camera_rig") as Node).get("camera")
	cam.current = true
	_giant.process_mode = Node.PROCESS_MODE_DISABLED   # held still: only the people change between two frames
	if _mode == "readability":
		await _readability(ROLES)
	elif _mode == "creatures":
		_cls("PersonRig").call("enable_for_tests")
		await _readability(CREATURES)
	else:
		await _render()
	print("PEOPLE_PROBE " + JSON.stringify(_out))
	quit(0)


static func _calls() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


static func _prims() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)


func _spawn(scene: String, record: String, id: String, pos: Vector3, yaw: float) -> Node3D:
	var e := (load(scene) as PackedScene).instantiate() as Node3D
	e.set("entity_id", id)
	e.set("ai_enabled", false)
	(e.get_node("CombatEntity") as Node).set("definition_id", record)
	e.position = pos
	e.rotation.y = yaw
	_root3d.add_child(e)
	return e


func _image() -> Image:
	await RenderingServer.frame_post_draw
	return get_root().get_viewport().get_texture().get_image()


## A skinned actor's screen box: the box of the pixels its Visual covers (a frame with it hidden against one with it
## shown).
func _box(a: Node3D) -> Rect2i:
	var vis := a.get_node("Visual") as Node3D
	var shown: Image = await _image()
	vis.visible = false
	await _frames(2)
	var hidden: Image = await _image()
	vis.visible = true
	await _frames(2)
	var r := Rect2i()
	var first := true
	for y in shown.get_height():
		for x in shown.get_width():
			var c1 := shown.get_pixel(x, y)
			var c2 := hidden.get_pixel(x, y)
			if absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) > 0.06:
				if first:
					r = Rect2i(x, y, 1, 1)
					first = false
				else:
					r = r.expand(Vector2i(x, y))
	return r.intersection(Rect2i(0, 0, shown.get_width(), shown.get_height()))


## [the pixels that differ by more than 0.08 in a channel, their box].
static func _diff_box(a: Image, b: Image) -> Array:
	var n := 0
	var r := Rect2i()
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > 0.08 or absf(ca.g - cb.g) > 0.08 or absf(ca.b - cb.b) > 0.08:
				r = Rect2i(x, y, 1, 1) if n == 0 else r.expand(Vector2i(x, y))
				n += 1
	return [n, r]


## The share of the pixels of `box` that differ by more than 0.08 in a channel.
static func _changed(a: Image, b: Image, box: Rect2i) -> float:
	var n := 0
	var total := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			total += 1
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > 0.08 or absf(ca.g - cb.g) > 0.08 or absf(ca.b - cb.b) > 0.08:
				n += 1
	return float(n) / float(maxi(total, 1))


func _render() -> void:
	var rig_cls: Object = _cls("PersonRig")
	rig_cls.call("set_cap", 16)
	await _frames(SETTLE)
	var base := _calls()
	var one := _spawn("res://scenes/enemies/soldier.tscn", "enemy.soldier", "probe.one", Vector3(2.0, 0.05, 0), PI)
	await _frames(SETTLE)
	_out["skinned"] = bool(one.get_node("Visual").call("skinned"))
	_out["one_calls"] = _calls() - base
	one.queue_free()
	await _frames(SETTLE)
	rig_cls.call("set_cap", 0)
	var crowd: Array = []
	for i in 40:
		crowd.append(_spawn("res://scenes/enemies/soldier.tscn", "enemy.soldier", "probe.crowd_%d" % i,
			Vector3(0.6 + (i % 8) * 1.4, 0.05, -2.0 - (i / 8) * 1.6), PI))
	await _frames(SETTLE * 2)
	var target: Node3D = crowd[3]
	var other: Node3D = crowd[5]
	var before: Image = await _image()
	target.call("flash", 1.0)
	await _frames(1)
	var after: Image = await _image()
	var dump := OS.get_environment("PEOPLE_PROBE_DUMP")
	if dump != "":
		before.save_png(dump + "/flash_before.png")
		after.save_png(dump + "/flash_after.png")
	var changed := _diff_box(before, after)
	_out["flash_pixels"] = changed[0]
	_out["flash_box"] = [changed[1].position.x, changed[1].position.y, changed[1].size.x, changed[1].size.y]
	await _frames(30)
	for a: Node3D in crowd:
		a.position.z -= 22.0   # the block at about 30 m from the giant
	await _frames(SETTLE * 2)
	_out["crowd_calls"] = _calls()
	_out["crowd_prims"] = _prims()
	rig_cls.call("set_cap", 16)
	await _frames(SETTLE)
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var rig_us := 0.0
	for k in 60:
		await process_frame
		frames += 1
	_out["mixed_calls"] = _calls()
	_out["mixed_prims"] = _prims()
	var skinned := 0
	for a: Node3D in crowd:
		skinned += 1 if bool(a.get_node("Visual").call("skinned")) else 0
	_out["mixed_skinned"] = skinned
	# the people's CPU a frame: the rigs' and the renderers' _process, timed by the engine's own monitor
	var us := [0, 0, 0]   # the skinned rigs, the instanced ones, the renderers
	for k in 30:
		await process_frame
		for a: Node3D in crowd:
			var v := a.get_node("Visual") as Node
			var t := Time.get_ticks_usec()
			v.call("_process", 1.0 / 60.0)
			us[0 if bool(v.call("skinned")) else 1] += Time.get_ticks_usec() - t
		var t2 := Time.get_ticks_usec()
		for r in get_nodes_in_group("crowd_renderers"):
			r.call("refresh")
		us[2] += Time.get_ticks_usec() - t2
	_out["people_cpu_ms"] = float(us[0] + us[1] + us[2]) / 30.0 / 1000.0
	_out["people_cpu_parts_ms"] = [float(us[0]) / 30000.0, float(us[1]) / 30000.0, float(us[2]) / 30000.0]
	_out["adapter"] = RenderingServer.get_video_adapter_name()


func _readability(list: Array) -> void:
	var data: Node = get_root().get_node("GameData")
	var results := []
	for spec: Array in list:
		var h := float((data.call("get_record", spec[1]) as Dictionary).get("height_m", 1.8))
		var ahead := maxf(4.0, h * 1.4) - 4.0
		for action: String in spec[2]:
			var a := _spawn(spec[0], spec[1], "probe.read_%d" % results.size(), Vector3(1.6 + ahead * 0.25, 0.05, 2.0 - ahead), PI)
			await _frames(SETTLE * 2)
			var box: Rect2i = await _box(a)
			var idle: Image = await _image()
			var c: Object = a.get("controller")
			if not (c.get("library") as Dictionary).has(action):
				c.call("add_action", data.call("get_action", action))
			c.call("request", &"attack", {"action_id": action})
			var started := c.get("action") != null
			var windup := 0.0
			var shot: Image = null
			for k in 240:
				await process_frame
				if c.get("action") == null:
					break
				if int(c.call("phase")) == 1:   # ActionDef.Phase.WINDUP
					windup = float(c.call("phase_fraction"))
					if windup >= 0.85:
						shot = await _image()
						break
				else:
					shot = await _image()
					break
			if shot != null:
				box = box.merge(await _box(a))   # the idle's box and the wind-up's
			var share := _changed(idle, shot, box) if shot != null else 0.0
			var dump := OS.get_environment("PEOPLE_PROBE_DUMP")
			if dump != "" and shot != null:
				idle.save_png("%s/read_%d_idle.png" % [dump, results.size()])
				shot.save_png("%s/read_%d_shot.png" % [dump, results.size()])
				print("box ", box)
			var rig := a.get_node("Visual")
			results.append({"role": spec[1], "action": action, "started": started, "share": share,
				"skinned": bool(rig.call("skinned")) if rig.has_method("skinned") else bool(rig.get("skinned"))})
			a.queue_free()
			await _frames(4)
	_out["results"] = results
