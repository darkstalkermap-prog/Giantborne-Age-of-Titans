extends SceneTree
## The static world's draw calls at the Kingsgate shelf, the six settlements' greens and (M8 gate, F27)
## the M8 regions' ten places (P25; plan M6-M9 §3.8, §5.2: at most 40 a view at `low` - "P25 and the
## region packages re-measure at the viewpoints"), as tests/slow/test_world_build.gd measures them in a
## child process under Xvfb (the headless test runner renders nothing). It needs a renderer:
##
##   xvfb-run -a -s "-screen 0 640x360x24" godot --path . --resolution 640x360 --audio-driver Dummy \
##     -s res://tests/support/world_draw_probe.gd -- --no-user-settings
##
## It loads scenes/world/world.tscn at the `low` preset without its encounter director (no actors)
## and with the giant still (processing off), loads the ring of chunks around each viewpoint at once
## (the streamer's own steps, synchronously), puts the stage-3 camera behind the viewpoint and turns
## it through four directions, and prints one line
##   WORLD_DRAWS {"views": {viewpoint: most draw calls of the static world (the giant hidden)},
##                "max": n, "with_giant": {viewpoint: the same views with the giant in them},
##                "renderer": ..., "adapter": ...}
## then quits. Everything is reached at run time (load(), call()), so the script compiles before the
## autoloads exist.

const WORLD := "res://scenes/world/world.tscn"
## Viewpoint -> [x, z]: the shelf's start checkpoint and the six settlements' greens (plan §5.4), then
## (M8 gate, F27) the Greywood's, the Drowned Steps', Aldmere's and the Stonehold's places of P35 and
## P36 at their POIs (the review's viewpoints, in its order; the chunks of earlier views stay loaded
## until they are three chunks away, as in play: the budget's worst case of up to 25).
const VIEWS := {"kingsgate_shelf": [-300, 916], "millford": [-380, 618], "brannock": [60, 565],
	"hollowmere": [-610, 22], "fort_aldmere": [650, -62], "skarn": [440, -640], "harroks_hall": [-560, -690],
	"woodcutters_camp": [-420, 220], "great_pines": [-560, -260], "bell_tower": [-200, -240],
	"titans_bones": [220, -260], "sunken_vault": [20, 30], "mere_of_kings": [-20, 20], "troll_den": [-760, -330],
	"war_camp": [520, 120], "moot_battery": [-190, -640], "ballista_ridge": [780, 20]}
const DIRECTIONS := 4
## The stage-3 camera (growth.03: pivot 7.25 m, arm 12 m, the rig's default pitch -18 degrees).
const PIVOT_M := 7.25
const ARM_M := 12.0
const PITCH_DEG := -18.0
const SETTLE_FRAMES := 3

var _world: Node3D = null
var _cam: Camera3D = null
var _started := false


func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var settings := get_root().get_node_or_null("Settings")
	if settings != null:
		settings.set("graphics_override", "low")
	_world = (load(WORLD) as PackedScene).instantiate()
	for n in ["EncounterDirector"]:
		var child := _world.get_node_or_null(n)
		if child != null:
			_world.remove_child(child)
			child.free()
	var player := _world.get_node_or_null("Player")
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	get_root().add_child(_world)
	_cam = Camera3D.new()
	_cam.far = 2400.0
	_cam.fov = 75.0
	_world.add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(2)
	var streamer: Object = _world.get("streamer")
	var player := _world.get_node_or_null("Player") as Node3D
	var out := {}
	var with_giant := {}
	var worst := 0
	for view: String in VIEWS:
		var xz: Array = VIEWS[view]
		var at := Vector3(float(xz[0]), 0.0, float(xz[1]))
		if streamer != null:
			var guard := 0
			while not bool(streamer.call("ring_ready", at)) and guard < 4000:
				streamer.call("load_ring_slice", at)
				guard += 1
		var ground := float(_world.call("height_at", at))
		at.y = ground if is_finite(ground) else 0.0
		if player != null:
			player.global_position = at
		var best := 0
		var best_giant := 0
		for k in DIRECTIONS:
			var yaw := TAU * float(k) / DIRECTIONS
			var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), yaw, 0.0))
			_cam.global_transform = Transform3D(basis, at + Vector3.UP * PIVOT_M + basis.z * ARM_M)
			# the static world alone, then with the giant standing in view
			if player != null:
				player.visible = false
			await _frames(SETTLE_FRAMES)
			best = maxi(best, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			if player != null:
				player.visible = true
				await _frames(SETTLE_FRAMES)
				best_giant = maxi(best_giant, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		out[view] = best
		with_giant[view] = best_giant
		worst = maxi(worst, best)
	print("WORLD_DRAWS " + JSON.stringify({"views": out, "max": worst, "with_giant": with_giant,
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"adapter": RenderingServer.get_video_adapter_name()}))
	quit(0)
