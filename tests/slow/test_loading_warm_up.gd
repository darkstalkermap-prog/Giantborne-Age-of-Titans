extends IntegrationSuite
## M10 gate (LD-2; plan M10 §3.5 item 5): the loading screen's warm-up in scripts/main.gd. With a display the
## loading gate ends with the camera put on the giant (frame_camera_on_player) and the finished level drawn
## WARM_FRAMES times behind "Loading..." (hold_until_drawn), so the first frame of play draws nothing for the
## first time. Before, the camera rig - which follows the giant in _process, and a paused tree runs none -
## stood at the level's own start through the whole load: after a Continue, where the save moves the giant to
## his shrine, every frame behind the loading screen looked at another part of the world, and the world's
## first frame took 3 to 4.6 median frames on the Web (2.0-2.5 natively with an empty shader cache; 1.1-1.2
## with the warm-up: docs/PERFORMANCE.md). Headless nothing is drawn, so the suite runs the gate with
## main.gd's force_warm_up and reads what it held, when the first tick ran and where the camera stood.

const MainScript := preload("res://scripts/main.gd")
const SCENE := "user://m10_gate_warm_level.tscn"
## Far from the suites' floor.
const FAR := Vector3(-900, 0, 900)

var _main: Node = null
var _first_tick: Dictionary = {}
var _preview_warmed_before := false


func before_each() -> void:
	await super()
	_preview_warmed_before = TitleScreen.preview_warmed
	TitleScreen.preview_warmed = true   # as after a title: the M10 gate's cases hold the level's frames only


func after_each() -> void:
	Sim.remove_hooks(self)
	MainScript.force_warm_up = false
	TitleScreen.preview_warmed = _preview_warmed_before
	GameSession.level_override = ""
	get_tree().paused = false
	if FileAccess.file_exists(SCENE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE))
	await super()


func _on_tick(_tick: int) -> void:
	if _first_tick.is_empty() and _main != null and is_instance_valid(_main):
		_first_tick = {"loading": bool(_main.call("is_loading")), "warm": int(_main.get("warm_frames_drawn")), "tick": Sim.tick}


## A level with a floor and the giant on it, saved as the scene main.gd loads.
func _save_level() -> void:
	var lv := Node3D.new()
	lv.name = "WarmLevel"
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = HitQueryAdapter.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(900, 1, 900)
	cs.shape = box
	ground.add_child(cs)
	ground.position = FAR + Vector3(0, -0.5, 0)
	lv.add_child(ground)
	var p := (load(GIANT) as PackedScene).instantiate() as GiantPlayer
	p.position = FAR + Vector3(0, 0.05, 0)
	lv.add_child(p)
	for n in [ground, cs, p]:
		n.owner = lv
	var packed := PackedScene.new()
	packed.pack(lv)
	lv.free()
	assert_eq(ResourceSaver.save(packed, SCENE), OK, "the test level is saved")
	GameSession.level_override = SCENE


func _load(main: Node) -> int:
	var tick0 := Sim.tick
	_main = main
	_first_tick = {}
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, _on_tick, 0)
	add_child(main)
	var guard := 0
	while bool(main.call("is_loading")) and guard < 240:
		assert_true(get_tree().paused, "the tree stays paused behind the loading screen (frame %d)" % guard)
		assert_eq(Sim.tick, tick0, "and no tick passes")
		guard += 1
		await get_tree().process_frame
	guard = 0
	while _first_tick.is_empty() and guard < 60:
		guard += 1
		await get_tree().process_frame
	Sim.remove_hooks(self)
	return tick0


func test_the_gate_holds_its_warm_frames_before_the_first_tick() -> void:
	_save_level()
	MainScript.force_warm_up = true
	var main := MainScript.new()
	assert_eq(int(main.get("warm_frames_drawn")), 0, "nothing held before a load")
	var tick0 := await _load(main)
	assert_true(bool(main.call("warm_up_wanted")), "a level and a display (forced here): the warm-up is wanted")
	assert_eq(int(main.get("warm_frames_drawn")), MainScript.WARM_FRAMES, "the level was held for its %d warm frames" % MainScript.WARM_FRAMES)
	assert_true(MainScript.WARM_FRAMES >= 2 and MainScript.WARM_LIMIT_S <= 10.0, "a few frames, a bounded wait")
	assert_false(_first_tick.is_empty(), "the level's first tick ran")
	if not _first_tick.is_empty():
		assert_eq([bool(_first_tick.loading), int(_first_tick.warm)], [false, MainScript.WARM_FRAMES],
			"only after the warm frames and with the loading screen gone")
		assert_true(int(_first_tick.tick) > tick0, "the simulation ticks then")
	assert_false(get_tree().paused, "and the game runs")
	main.queue_free()
	await get_tree().process_frame


func test_the_camera_is_put_on_the_giant_while_the_tree_is_paused() -> void:
	_save_level()
	var main := MainScript.new()
	await _load(main)
	assert_false(bool(main.call("warm_up_wanted")), "headless: no warm-up (nothing is drawn)")
	assert_eq(int(main.get("warm_frames_drawn")), 0, "and no frame held: a headless load is as long as it was")
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	assert_true(p != null and p.camera_rig != null, "the level's giant and his camera")
	if p == null:
		main.queue_free()
		return
	# a save's restore: the giant set down at his shrine, far from the level's own start, in a paused tree
	get_tree().paused = true
	var tick := Sim.tick
	p.global_position = FAR + Vector3(300, 0.05, -200)
	await get_tree().process_frame
	await get_tree().process_frame
	var away := p.camera_rig.global_position.distance_to(p.global_position)
	assert_true(away > 250.0, "a paused tree leaves the camera where the giant was (%.0f m away)" % away)
	assert_true(bool(main.call("frame_camera_on_player")), "the loading screen frames the giant")
	var near := p.camera_rig.global_position.distance_to(p.global_position)
	assert_true(near < 20.0, "the camera stands behind him (%.1f m)" % near)
	assert_eq(Sim.tick, tick, "without a tick")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var hold := src.substr(src.find("func hold_until_drawn("), 700)
	assert_true(hold.find("frame_camera_on_player()") > 0 and hold.find("frame_camera_on_player()") < hold.find("await get_tree().process_frame"),
		"hold_until_drawn frames the giant before its frames are drawn")
	var ready := src.substr(src.find("func _ready()"), 2600)
	assert_true(ready.find("await hold_until_drawn(loading)") > ready.find("await hold_until_navigation_ready(nav_built)")
		and ready.find("await hold_until_drawn(loading)") < ready.find("loading.queue_free()"),
		"the warm-up is the gate's last hold, behind the loading label")
	get_tree().paused = false
	main.queue_free()
	await get_tree().process_frame


## P49 (plan M11 §3.2 item 8): a start that passed no title (--continue on the command line) warms the
## creator's preview behind the loading screen too; after a title, or once it is done, nothing more is held.
func test_a_start_without_a_title_warms_the_preview_behind_the_loading_screen() -> void:
	_save_level()
	MainScript.force_warm_up = true
	TitleScreen.preview_warmed = false
	var main := MainScript.new()
	var tick0 := await _load(main)
	assert_eq(int(main.get("warm_frames_drawn")), MainScript.WARM_FRAMES, "the level's warm frames as before")
	assert_eq(int(main.get("preview_frames_drawn")), GiantPreview.WarmUp.FRAMES_EACH * 2,
		"then the preview's warm-up: its frames under the studio's light and under a level's")
	assert_true(TitleScreen.preview_warmed, "and the process knows the preview is warm")
	assert_false(_first_tick.is_empty(), "the level's first tick ran")
	if not _first_tick.is_empty():
		assert_true(not bool(_first_tick.loading) and int(_first_tick.tick) > tick0, "only after the loading screen let go")
	assert_eq(main.find_children("GiantWarmUp*", "SubViewport", true, false).filter(
		func(n: Node) -> bool: return not n.is_queued_for_deletion()).size(), 0, "the warm-up's viewport is freed")
	main.queue_free()
	await get_tree().process_frame
	# A second load in the same process (a travel, a Continue after the title): nothing more is held.
	_save_level()
	var again := MainScript.new()
	await _load(again)
	assert_eq(int(again.get("preview_frames_drawn")), 0, "a warm preview is not warmed again")
	assert_eq(int(again.get("warm_frames_drawn")), MainScript.WARM_FRAMES, "the level's frames still are")
	again.queue_free()
	await get_tree().process_frame
	# The title's own warm-up sets the same flag (ui/screens/title_screen.gd).
	var src := FileAccess.get_file_as_string("res://ui/screens/title_screen.gd")
	assert_true(src.contains("preview_warmed = true   # P49"), "the title marks the preview warm when its warm-up is done")


func test_headless_no_preview_is_warmed() -> void:
	_save_level()
	TitleScreen.preview_warmed = false
	var main := MainScript.new()
	await _load(main)
	assert_eq(int(main.get("preview_frames_drawn")), 0, "headless: nothing is drawn, nothing is held")
	assert_false(TitleScreen.preview_warmed, "and the flag stays as it was")
	main.queue_free()
	await get_tree().process_frame
