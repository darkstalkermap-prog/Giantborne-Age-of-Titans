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
##     --scenario=capture_c1 [--c1-walk] --skin --capture-dir=<out>
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
	WorldState.set_flag("campaign.completed", true)


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
	return [
		["millford", 5.0, func() -> void:
			_grow(8)
			_at(-372, 652, Vector3(-440, 0, 600)),
			{}, [[1.5, "stage8_in_millford", {}]], func(_t: float) -> void: _view_set(_cam_at(-420, 600, 1.6, -372, 652, 22.0, 72.0))],
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
			_at(-180, -1240, Vector3(-214, 0, -1272)),
			{}, [[2.0, "last_hearth_under_a_colossus", {}], [3.5, "last_hearth_wide", _cam_at(-120, -1340, 40.0, -200, -1260, 4.0, 60.0)]],
			func(t: float) -> void:
				if t < 3.0:
					_view_set(_cam_at(-232, -1290, 1.7, -180, -1240, 20.0, 74.0))],
		["rimkin", 7.0, func() -> void:
			_at(70, -1400, Vector3(40, 0, -1448)),
			{}, [[4.0, "rimkin_by_the_fallen_king", {}]], func(_t: float) -> void: _view_set(_cam_at(120, -1360, 30.0, 50, -1440, 10.0, 60.0))],
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
			{}, [[3.5, "dire_wolves", {}]], func(_t: float) -> void: _view_set(_cam_at(-130, -1350, 22.0, -185, -1400, 3.0, 60.0))],
		["far_view", 6.0, func() -> void:
			_grow(7)
			_at(452, -1612, Vector3(380, 0, -1772)),
			{}, [[3.0, "far_view_of_the_hoarcrown", {}]], func(_t: float) -> void: _view_set({"at": _floor(500, -1580) + Vector3.UP * 40.0,
				"look": Vector3(380, 520, -1772), "fov": 50.0})],
		["map", 4.0, func() -> void:
			_ui("map", true),
			{}, [[2.0, "map_with_the_hoarfell", {}]], func(_t: float) -> void: pass],
		["character", 4.0, func() -> void:
			_ui("map", false)
			_ui("character", true),
			{}, [[2.0, "character_growth_track_stage7", {}]], func(_t: float) -> void: pass],
		["end", 1.0, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
	]


## beyond_the_rim: about 40 s - a stage-6 giant walks up the Breach from the Stonehold into the Hoarfell, a chase
## camera behind and above it, then turns toward the Fallen King and the Rimstone.
func _walk_beats() -> Array:
	return [
		["walk_breach", 26.0, func() -> void:
			_grow(6)
			_at(150, -840, Vector3(150, 0, -1300))
			_walk(Vector2(0, 1)),
			{}, [[1.0, "walk_start", {}], [13.0, "walk_mid", {}], [25.0, "walk_top", {}]],
			func(_t: float) -> void: _chase(34.0, 16.0)],
		["walk_upland", 16.0, func() -> void:
			_face(_p, Vector3(-70, 0, -1460))
			_p.camera_rig.yaw = _p.facing_yaw
			_walk(Vector2(0, 1)),
			{}, [[8.0, "walk_upland", {}]], func(_t: float) -> void: _chase(38.0, 18.0)],
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
