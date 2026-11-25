class_name CaptureC1
extends CaptureQuarry
## C1: the colossi's and the land beyond the rim's capture tour - --scenario=capture_c1 in the real world saves a
## still at each moment the beats name (c1_NN_<moment>.png under user://captures or --capture-dir=): a stage-8 giant
## in Millford and by Fort Aldmere (the old world's scale), each new ability (Colossus Stride over Millford's barn,
## Shattering Tread, Mountain Hurl and Worldshaking Roar at the Rimward's camp), the Breach from the Stonehold, mid-climb
## and from its top, the Hoarfell's landmarks (the causeway, the Fallen King, the chain anchors, the Rimstone, Last
## Hearth with a colossus over its tents), its encounters (the rimkin, the warband, the trolls, the dire wolves), the
## Hoarwatch's far view of the Hoarcrown, the map with the new land and the Character menu's growth track at stage 7;
## with --c1-walk, only the walk up the Breach into the Hoarfell (beyond_the_rim's movie, about 40 s):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/beyond_the_rim.avi] -- --no-user-settings --mode=world --start=world.cp.cairnlands \
##     --scenario=capture_c1 [--c1-walk | --c1-beats=millford,stride,...] --skin --capture-dir=<out>
##
## As CaptureQuarry's tour: fixed cameras, the giant healed every tick, the HUD hidden (shown for the two menus).

const SHOT_PREFIX_C1 := "c1"
const WAIT := Vector3(96, 80, -556)

var walk_only := false
var _layer: CanvasLayer = null


func _init(autopilot: Node) -> void:
	walk_only = OS.get_cmdline_user_args().has("--c1-walk")
	super(autopilot)


## No titan to wait for: the tour sets up at once.
func step(player: GiantPlayer, dt: float) -> bool:
	if done:
		return true
	if not _ready_done:
		_p = player
		_p.router.use_injection = true
		_world = player.get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot
		if _world == null:
			notes.append("no world (run it with --mode=world)")
			done = true
			return true
		_go(WAIT)
		_setup()
		_ready_done = true
		titan_found = true
	return super(player, dt)


func _setup() -> void:
	Settings.set_value("damage_numbers", false, false)
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		_layer = layer
		_layer.visible = false
	WorldState.set_flag("act.two.begun", true)
	# (act one already over, as after the finale: written quietly, or the Stone Throne would play the finale and
	# open the end screen over the tour)
	WorldState.flags["campaign.completed"] = true
	GameSession.expansion["act"] = 2


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_C1, n, moment]


func _grow(stage: int) -> void:
	TitanDuel.prepare(_p, stage)
	for id: String in ["ability.colossus_stride", "ability.titan_stomp", "ability.earthquake", "ability.crag_hurl",
			"ability.titan_roar", "ability.shattering_tread", "ability.mountain_hurl", "ability.worldshaking_roar"]:
		var a := GameData.get_action(id)
		if a != null and a.unlock_stage <= stage and not _p.known_abilities.has(id):
			_p.progression.learn_ability(id, "capture")


## The giant set on the ground at (x, z), facing `to`.
func _at(x: float, z: float, to: Vector3 = Vector3.INF) -> void:
	_go(Vector3(x, 0.0, z))
	if to.is_finite():
		_face(_p, to)
	_p.camera_rig.yaw = _p.facing_yaw   # (movement is camera-relative: forward is where it faces)


## The ground at (x, z), its ring streamed in first when it is not (a camera far from the giant).
func _floor(x: float, z: float) -> Vector3:
	if _world != null and is_nan(_world.height_at(Vector3(x, 0, z))):
		var at := Vector3(x, 0, z)
		var guard := 0
		while not _world.streamer.ring_ready(at) and guard < 400:
			_world.streamer.load_ring_slice(at)
			guard += 1
	return super(x, z)


## A fixed camera over the ground: `dy` m over the ground at (x, z), looking at (lx, ly over its ground, lz).
func _cam_at(x: float, z: float, dy: float, lx: float, lz: float, ly: float, fov := 55.0) -> Dictionary:
	return {"at": _floor(x, z) + Vector3.UP * dy, "look": _floor(lx, lz) + Vector3.UP * ly, "fov": fov}


func _force(id: String) -> void:
	var a := GameData.get_action(id)
	if a != null:
		_p.controller.force_action(a)


func _ui(screen: String, on: bool) -> void:
	if _layer != null:
		_layer.visible = on
	var stack := _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack
	if stack == null:
		return
	if on:
		stack.open(screen, {})
	else:
		stack.close_all() if stack.has_method("close_all") else stack.close_top()


func _make_beats() -> Array:
	if OS.get_cmdline_user_args().has("--c1-walk"):
		return _walk_beats()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--c1-beats="):
			only = arg.substr(11)
	var all := _tour_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


func _tour_beats() -> Array:
	return [
		["millford", 5.0, func() -> void:
			_grow(8)
			_at(-372, 652, Vector3(-310, 0, 640)),
			{}, [[1.5, "stage8_in_millford", {}]], func(_t: float) -> void: _view_set(_cam_at(-310, 640, 2.0, -372, 652, 18.0, 74.0))],
		["millford_wide", 4.0, func() -> void: pass,
			{}, [[1.5, "stage8_over_millford", {}]], func(_t: float) -> void: _view_set(_cam_at(-300, 600, 30.0, -385, 640, 14.0, 58.0))],
		["stride", 4.0, func() -> void:
			_at(-372, 652, Vector3(-440, 0, 600))
			_force("ability.colossus_stride"),
			{}, [[0.45, "stride_over_millford", {}], [1.6, "stride_landing", {}]],
			func(_t: float) -> void: _view_set(_cam_at(-330, 700, 18.0, -400, 630, 14.0, 62.0))],
		["aldmere", 5.0, func() -> void:
			_at(540, -150, Vector3(650, 0, -170)),
			{}, [[1.5, "stage8_at_fort_aldmere", {}]], func(_t: float) -> void: _view_set(_cam_at(470, -110, 22.0, 610, -170, 18.0, 60.0))],
		["breach_from_stonehold", 5.0, func() -> void:
			_grow(6)
			_at(150, -860, Vector3(150, 0, -1100)),
			{}, [[2.0, "breach_from_the_stonehold", {}]], func(_t: float) -> void: _view_set(_cam_at(170, -740, 26.0, 150, -1000, 70.0, 56.0))],
		["breach_mid", 5.0, func() -> void:
			_at(150, -1040, Vector3(150, 0, -1300)),
			{}, [[2.0, "breach_mid_climb", {}]], func(_t: float) -> void: _view_set(_cam_at(160, -990, 22.0, 150, -1060, 14.0, 58.0))],
		["breach_beyond", 5.0, func() -> void:
			_at(150, -1236, Vector3(150, 0, -900)),
			{}, [[2.0, "breach_from_beyond", {}]], func(_t: float) -> void: _view_set(_cam_at(176, -1300, 30.0, 150, -1000, -20.0, 56.0))],
		["causeway", 5.0, func() -> void:
			_grow(7)
			_at(96, -1296, Vector3(-20, 0, -1404)),
			{}, [[2.0, "kings_causeway", {}]], func(_t: float) -> void: _view_set(_cam_at(170, -1240, 34.0, 40, -1350, 14.0, 58.0))],
		["fallen_king", 5.0, func() -> void:
			_at(30, -1392, Vector3(110, 0, -1440)),
			{}, [[2.0, "the_fallen_king", {}]], func(_t: float) -> void: _view_set(_cam_at(-20, -1340, 30.0, 100, -1440, 10.0, 60.0))],
		["chains", 5.0, func() -> void:
			_at(318, -1352, Vector3(380, 0, -1420)),
			{}, [[2.0, "chain_anchors", {}]], func(_t: float) -> void: _view_set(_cam_at(270, -1320, 40.0, 380, -1420, 20.0, 60.0))],
		["rimstone", 5.0, func() -> void:
			_at(-60, -1450, Vector3(-70, 0, -1510)),
			{}, [[2.0, "the_rimstone", {}]], func(_t: float) -> void: _view_set(_cam_at(10, -1400, 30.0, -70, -1500, 30.0, 58.0))],
		["hearth", 5.0, func() -> void:
			_at(-236, -1294, Vector3(-178, 0, -1232)),
			{}, [[2.0, "last_hearth_under_a_colossus", {}], [3.5, "last_hearth_wide", {"at": Vector3(-130, 236, -1330), "look": Vector3(-205, 184, -1262), "fov": 60.0}]],
			func(t: float) -> void:
				if t < 3.0:
					_view_set(_cam_at(-176, -1230, 1.7, -214, -1272, 14.0, 74.0))],
		["rimkin", 7.0, func() -> void:
			_at(20, -1365, Vector3(60, 0, -1420)),
			{}, [[4.0, "rimkin_by_the_fallen_king", {}]], func(_t: float) -> void: _view_set(_cam_at(110, -1330, 34.0, 50, -1420, 8.0, 64.0))],
		["warband", 7.0, func() -> void:
			_grow(6)
			_at(230, -1270, Vector3(290, 0, -1312)),
			{}, [[4.0, "the_rimward_warband", {}]], func(_t: float) -> void: _view_set(_cam_at(200, -1240, 30.0, 290, -1312, 4.0, 58.0))],
		["shatter", 4.0, func() -> void:
			_grow(7)
			_at(250, -1280, Vector3(300, 0, -1318))
			_force("ability.shattering_tread"),
			{}, [[1.0, "shattering_tread", {}]], func(_t: float) -> void: _view_set(_cam_at(190, -1250, 34.0, 290, -1312, 4.0, 58.0))],
		["hurl", 5.0, func() -> void:
			_grow(8)
			_at(180, -1250, Vector3(322, 0, -1338))
			_force("ability.mountain_hurl"),
			{}, [[1.0, "mountain_hurl_thrown", {}], [2.6, "mountain_hurl_lands", {}]],
			func(_t: float) -> void: _view_set(_cam_at(170, -1180, 50.0, 260, -1300, 10.0, 60.0))],
		["roar", 5.0, func() -> void:
			_at(262, -1288, Vector3(300, 0, -1318))
			_force("ability.worldshaking_roar"),
			{}, [[2.4, "worldshaking_roar_routs", {}]], func(_t: float) -> void: _view_set(_cam_at(210, -1240, 44.0, 290, -1312, 4.0, 62.0))],
		["trolls", 7.0, func() -> void:
			_grow(6)
			_at(-330, -1380, Vector3(-362, 0, -1400)),
			{}, [[4.0, "crag_trolls", {}]], func(_t: float) -> void: _view_set(_cam_at(-290, -1350, 24.0, -350, -1400, 6.0, 60.0))],
		["wolves", 7.0, func() -> void:
			_at(-160, -1380, Vector3(-190, 0, -1400)),
			{}, [[3.5, "dire_wolves", {}]], func(_t: float) -> void: _view_set(_cam_at(-140, -1356, 12.0, -185, -1400, 2.0, 55.0))],
		["far_view", 6.0, func() -> void:
			_grow(7)
			_at(452, -1612, Vector3(380, 0, -1772)),
			{}, [[3.0, "far_view_of_the_hoarcrown", {}]], func(_t: float) -> void: _view_set({"at": _p.global_position + Vector3(20, 30, 50),
				"look": Vector3(380, 560, -1772), "fov": 70.0})],
		# C1b: the land beyond the rim's look - new viewpoints
		["fallen_king_side", 5.0, func() -> void:
			_grow(7)
			_at(30, -1470, Vector3(102, 0, -1426)),
			{}, [[2.0, "the_fallen_king_from_his_side", {}]], func(_t: float) -> void: _view_set(_cam_at(16, -1500, 44.0, 98, -1424, 4.0, 58.0))],
		["breach_gorge", 5.0, func() -> void:
			_grow(6)
			_at(150, -960, Vector3(150, 0, -1200)),
			{}, [[2.0, "the_breach_gorge_looking_up", {}]], func(_t: float) -> void: _view_set(_cam_at(142, -918, 14.0, 152, -1090, 70.0, 62.0))],
		["upland", 5.0, func() -> void:
			_at(150, -1244, Vector3(0, 0, -1400)),
			{}, [[2.0, "the_hoarfell_from_the_breach_top", {}]], func(_t: float) -> void: _view_set(_cam_at(176, -1226, 70.0, -60, -1420, 0.0, 60.0))],
		["storm", 5.0, func() -> void:
			_at(150, -1244, Vector3(380, 0, -1772)),
			{}, [[3.0, "the_storm_on_the_hoarcrown", {}]], func(_t: float) -> void: _view_set(_cam_at(140, -1236, 40.0, 380, -1772, -40.0, 40.0))],
		["hearth_close", 5.0, func() -> void:
			_at(-150, -1300, Vector3(-214, 0, -1272)),
			{}, [[2.5, "last_hearth_among_the_tents", {}]], func(_t: float) -> void: _view_set(_cam_at(-176, -1318, 5.0, -226, -1262, 4.0, 66.0))],
		["scatter", 5.0, func() -> void:
			_at(-40, -1290, Vector3(-120, 0, -1380)),
			{}, [[2.0, "the_upland_close", {}]], func(_t: float) -> void: _view_set(_cam_at(-60, -1300, 6.0, -140, -1380, 2.0, 62.0))],
		["map", 4.0, func() -> void:
			_ui("map", true),
			{}, [[2.0, "map_with_the_hoarfell", {}]], func(_t: float) -> void: pass],
		["character", 4.0, func() -> void:
			_ui("map", false)
			_ui("character", true),
			{}, [[2.0, "character_growth_track_stage7", {}]], func(_t: float) -> void: pass],
		["end", 1.0, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
	]


## beyond_the_rim: about 68 s - a stage-6 giant (8.1 m/s) walks up the Breach from the Stonehold into the Hoarfell, a chase
## camera behind and above it; at the top it turns along the Kings' Causeway toward the Fallen King with the camera
## raised over the upland, which then lifts and pans from the causeway and Last Hearth's smoke to the storm on the
## Hoarcrown (C1b: C1's walk turned too early and ended facing the rim's wall).
func _walk_beats() -> Array:
	return [
		["walk_breach", 44.0, func() -> void:
			_grow(6)
			_at(150, -880, Vector3(150, 0, -1300))
			_walk(Vector2(0, 1)),
			{}, [[1.0, "walk_start", {}], [20.0, "walk_mid", {}], [42.0, "walk_top", {}]],
			func(_t: float) -> void: _chase(34.0, 16.0)],
		["walk_upland", 14.0, func() -> void:
			_face(_p, Vector3(40, 0, -1420))
			_p.camera_rig.yaw = _p.facing_yaw
			_walk(Vector2(0, 1)),
			{}, [[7.0, "walk_upland", {}]], func(t: float) -> void: _chase(lerpf(34.0, 52.0, minf(t / 4.0, 1.0)), lerpf(16.0, 34.0, minf(t / 4.0, 1.0)))],
		["walk_vista", 10.0, func() -> void:
			_walk(Vector2(0, 1)),
			{}, [[5.0, "walk_vista_causeway", {}], [9.5, "walk_vista_hoarcrown", {}]], func(t: float) -> void:
				var u := smoothstep(0.0, 1.0, clampf(t / 9.0, 0.0, 1.0))
				var yaw := _p.facing_yaw
				var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
				var h := float(_p.profile.get("height_m", 18.9))
				var at := _p.global_position - fwd * lerpf(52.0, 30.0, u) + Vector3.UP * (h + lerpf(34.0, 90.0, u))
				var look := (_p.global_position + fwd * 80.0 + Vector3.UP * h).lerp(Vector3(380, 560, -1772), u)
				_view_set({"at": at, "look": look, "fov": lerpf(60.0, 50.0, u)})],
	]


## The camera behind the giant, `back` m behind and `up` m over its head, looking a little ahead of it.
func _chase(back: float, up: float) -> void:
	var yaw := _p.facing_yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var h := float(_p.profile.get("height_m", 18.9))
	_view_set({"at": _p.global_position - fwd * back + Vector3.UP * (h + up), "look": _p.global_position + fwd * 30.0 + Vector3.UP * h * 0.7,
		"fov": 60.0})


func _view_set(v: Dictionary) -> void:
	_view = v
