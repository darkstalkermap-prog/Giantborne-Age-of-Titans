class_name CaptureD3
extends CaptureC1
## D3: stage 9's capture tour - --scenario=capture_d3 in the real world saves a still at each moment the beats name
## (d3_NN_<moment>.png under user://captures or --capture-dir=): the Rimstone's refusals (stage 8 before the
## Frostbound's fall, stage 9 before the Stormcaller's, and the level), the growth 8 -> 9 at the Rimstone (before,
## during, after: GrowthMoment's swell), the Character menu's growth track at stage 9, a stage-9 giant in each land
## from the gameplay camera and from his own eyes (Last Hearth, Millford in the Crownmarch, Fort Aldmere's walls, the
## Greywood, the Stormstair, the Rimeglass), what only stage 9 does (Colossus Stride over one of Fort Aldmere's 16 m
## towers that a stage-8 stride refuses; the rimkin by the Fallen King breaking at the sight of him; the Fallen King's
## crown-iron on his shin), and each titan weapon on the stage-9 body, front and back. With --d3-film only the film:
## the growth at the Rimstone and a walk through Millford (about 55 s):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/d3_stage9.avi] -- --no-user-settings --mode=world --start=world.cp.last_hearth \
##     --scenario=capture_d3 [--d3-film | --d3-beats=growth,lands,...] --skin --capture-dir=<out>
##
## As CaptureC1's tour: fixed cameras (or the giant's own: "game"; his eyes: "eye"), the giant healed every tick, the
## HUD hidden (shown for the refusals and the menu).

const SHOT_PREFIX_D3 := "d3"
const RIMSTONE_SHRINE := "world.shrine.rimstone"
const WEAPONS := ["weapon.club_greatforged", "weapon.rime_maul_greathafted", "weapon.bell_hammer",
	"weapon.hammer_greatforged", "weapon.axe_greatforged", "weapon.sword_greatforged", "weapon.fists_greatforged"]
const SHIN := "world.hoarfell.fallen_king_shin"

var film_only := false


func _init(autopilot: Node) -> void:
	film_only = OS.get_cmdline_user_args().has("--d3-film")
	super(autopilot)


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_D3, n, moment]


func _setup() -> void:
	super()
	WorldState.set_flag("visited.world.shrine.rimstone", true)


## "game": the giant's own third-person camera, turned to `yaw_off` degrees off his facing and `pitch` down; "eye":
## a camera at his eyes looking where he faces, `down` degrees down; else CaptureC1's fixed views.
func _place_camera(view: Dictionary) -> void:
	if bool(view.get("game", false)):
		_p.camera_rig.yaw = _p.facing_yaw + deg_to_rad(float(view.get("yaw_off", 0.0)))
		_p.camera_rig.pitch = deg_to_rad(-float(view.get("pitch", 16.0)))
		_p.camera_rig.camera.make_current()
		return
	if bool(view.get("eye", false)):
		var yaw := _p.facing_yaw + deg_to_rad(float(view.get("yaw_off", 0.0)))
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var h := float(_p.profile.get("height_m", 3.66)) * float(_p.profile.get("eye_height_ratio", 0.92))
		var at := _p.global_position + Vector3.UP * h + fwd * float(_p.profile.get("capsule_radius_m", 1.0)) * 0.6
		var down := deg_to_rad(float(view.get("down", 12.0)))
		var look := at + fwd * cos(down) * 50.0 + Vector3.DOWN * sin(down) * 50.0
		super({"at": at, "look": look, "fov": float(view.get("fov", 70.0))})
		return
	super(view)


## The rimkin round the Fallen King: each one's state (the tour's notes: the scatter's evidence).
func _note_rimkin() -> void:
	for n in _p.get_tree().get_nodes_in_group("enemies"):
		var e: Variant = n.get("entity")
		if e is CombatEntity and str((e as CombatEntity).definition_id).begins_with("enemy.rimkin"):
			var b: Variant = n.get("brain")
			notes.append("rimkin %s: awe_broken %s, state %s" % [str(n.get("entity_id")), str(b.get("awe_broken")) if b != null else "?",
				str(EnemyBrain.AIState.keys()[int(b.get("state"))]) if b != null else "?"])


func _shrine() -> Node:
	for n in _p.get_tree().get_nodes_in_group("shrines"):
		if str(n.get("world_id")) == RIMSTONE_SHRINE:
			return n
	return null


func _try_grow(stage: int) -> void:
	var s := _shrine()
	if s == null:
		notes.append("the Rimstone's shrine is not loaded")
		return
	var r: Dictionary = _p.growth.grow_to(stage, s)
	if not bool(r.ok):
		notes.append("grow to %d: %s (%s)" % [stage, str(r.reason), str(r.get("message", ""))])


func _set_level(level: int) -> void:
	var prog = _p.progression
	if int(prog.level) < level:
		prog.add_xp(Progression.xp_for_level(level) - int(prog.xp), "capture")
	_p.controller.level = int(prog.level)


func _hud(on: bool) -> void:
	if _layer != null:
		_layer.visible = on


func _pickup(id: String) -> void:
	for n in _p.get_tree().get_nodes_in_group("interactables"):
		if str(n.get("world_id")) == id:
			_p.interact.use_candidate({"node": n, "id": id, "prompt": "", "priority": 0, "distance": 0.0})
			return
	notes.append("%s is not loaded" % id)


func _make_beats() -> Array:
	if film_only:
		return _film_beats()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--d3-beats="):
			only = arg.substr(11)
	var all := _tour_beats()
	if only == "strideprobe":
		return [["strideprobe", 0.5, func() -> void: _stride_probe(), {}, [], func(_t: float) -> void: pass]]
	if only == "":
		return all
	var names := only.split(",", false)
	if "dgate" in names:
		all.append_array(_dgate_beats())
	return all.filter(func(b: Array) -> bool: return str(b[0]) in names or str(b[0]).get_slice("_", 0) in names)


## Round the Rimstone: the giant south of its pad facing the stone (north).
func _at_rimstone() -> void:
	_at(-78, -1446, Vector3(-78, 0, -1510))


## The growth seen from the giant's side, the Rimstone behind him: low, a little below his middle.
func _growth_view() -> Dictionary:
	var c := _p.global_position
	var at := _floor(c.x + 68.0, c.z + 18.0)
	return {"at": Vector3(at.x, maxf(at.y, c.y) + 9.0, at.z), "look": c + Vector3(0, 17.0, -6.0), "fov": 58.0}


func _rimstone_view(dist: float, h: float, side := 1.0) -> Dictionary:
	return _cam_at(-78 + 34.0 * side, -1446 + dist, h, -78, -1452, 22.0, 60.0)


## A probe (--d3-beats=strideprobe): Colossus Stride's plan at stages 8 and 9 round each of Fort Aldmere's corner
## towers, from eight sides, the tower half the vault ahead (its notes; the tour's stride beats use a spot it found).
func _stride_probe() -> void:
	var v: Dictionary = GameData.get_action("ability.colossus_stride").param("vault")
	for c: Vector2 in [Vector2(560, -245), Vector2(740, -245), Vector2(740, -95), Vector2(560, -95)]:
		for k in 8:
			var a := TAU * float(k) / 8.0
			var dir := Vector2(cos(a), sin(a))
			var out := PackedStringArray()
			for st: int in [8, 9]:
				_grow(st)
				var half := 0.65 * float(_p.profile.get("height_m", 30.0))
				var at := c + dir * half
				_at(at.x, at.y, Vector3(c.x, 0, c.y))
				out.append("%d:%s" % [st, str(_p.motor.plan_vault(v).get("reason", "ok"))])
			notes.append("tower %s from %d deg: %s" % [c, k * 45, " ".join(out)])


func _tour_beats() -> Array:
	var beats: Array = [
		# the refusals at the Rimstone
		["refusal_8", 4.0, func() -> void:
			_grow(7)
			_set_level(15)
			_at_rimstone()
			_hud(true)
			_try_grow(8),
			{}, [[0.6, "shrine_refuses_stage8_frostbound_alive", {}]], func(_t: float) -> void: _view_set(_rimstone_view(60, 20))],
		["refusal_9", 4.0, func() -> void:
			WorldState.set_flag("boss.frostbound.defeated", true)
			_grow(8)
			_set_level(16)
			_at_rimstone()
			_try_grow(9),
			{}, [[0.6, "shrine_refuses_stage9_stormcaller_alive", {}]], func(_t: float) -> void: _view_set(_rimstone_view(70, 24))],
		["refusal_level", 4.0, func() -> void:
			WorldState.set_flag("boss.stormcaller.defeated", true)
			WorldState.set_flag("boss.stormcaller.outcome", "slain")
			WorldState.set_flag("boss.frostbound.outcome", "slain")
			_try_grow(9),
			{}, [[0.6, "shrine_refuses_stage9_level16", {}]], func(_t: float) -> void: _view_set(_rimstone_view(70, 24))],
		# the growth 8 -> 9
		["growth_track8", 3.0, func() -> void: _ui("character", true),
			{}, [[2.0, "growth_track_stage8_stage9_next", {}]], func(_t: float) -> void: pass],
		["growth_track8end", 0.5, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
		["growth_before", 2.5, func() -> void:
			_hud(false)
			_set_level(17)
			_at_rimstone(),
			{}, [[1.5, "growth_8to9_before", {}]], func(_t: float) -> void: _view_set(_growth_view())],
		["growth_swell", 5.0, func() -> void: _try_grow(9),
			{}, [[0.5, "growth_8to9_swelling", {}], [1.7, "growth_8to9_halfway", {}], [4.6, "growth_8to9_after", {}]],
			func(_t: float) -> void: _view_set(_growth_view())],
		["growth_game", 3.0, func() -> void: pass,
			{"game": true, "yaw_off": 160.0, "pitch": 10.0}, [[2.0, "growth_after_gameplay_camera", {"game": true, "yaw_off": 160.0, "pitch": 10.0}]], null],
		["track", 3.0, func() -> void: _ui("character", true),
			{}, [[2.0, "growth_track_stage9", {}]], func(_t: float) -> void: pass],
		["trackend", 0.5, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
	]
	# a stage-9 giant in each land: the gameplay camera and his own eyes
	var lands := [["last_hearth", -150.0, -1300.0, Vector3(-214, 0, -1272)], ["millford", -320.0, 600.0, Vector3(-385, 0, 645)],
		["aldmere", 650.0, -10.0, Vector3(650, 0, -170)], ["greywood", -500.0, 150.0, Vector3(-600, 0, 60)],
		["stormstair", -96.0, -330.0, Vector3(-96, 0, -428)], ["rimeglass", 590.0, -1545.0, Vector3(640, 0, -1610)]]
	for l: Array in lands:
		var nm := str(l[0])
		var x := float(l[1])
		var z := float(l[2])
		var to: Vector3 = l[3]
		beats.append(["lands_%s" % nm, 4.5, func() -> void:
			_grow(9)
			_at(x, z, to),
			{"game": true, "yaw_off": 0.0, "pitch": 14.0},
			[[2.5, "stage9_%s_gameplay" % nm, {"game": true, "yaw_off": 0.0, "pitch": 14.0}],
				[4.0, "stage9_%s_giants_eye" % nm, {"eye": true, "down": 14.0}]], null])
	beats.append_array([
		# only at stage 9: over one of Fort Aldmere's 16 m towers (its south-east corner)
		["stride_refused", 3.0, func() -> void:
			_grow(8)
			_hud(true)
			_at(756.3, -78.7, Vector3(740, 0, -95))
			var plan: Dictionary = _p.motor.plan_vault(GameData.get_action("ability.colossus_stride").param("vault"))
			notes.append("stage-8 stride at the tower: %s" % str(plan.get("reason", "ok")))
			_force("ability.colossus_stride"),
			{}, [[0.8, "stride_refused_at_stage8_tower", {}]], func(_t: float) -> void: _view_set(_cam_at(800, -30, 30.0, 740, -95, 14.0, 58.0))],
		["stride_over", 4.0, func() -> void:
			_hud(false)
			_grow(9)
			_at(756.3, -78.7, Vector3(740, 0, -95))
			var plan: Dictionary = _p.motor.plan_vault(GameData.get_action("ability.colossus_stride").param("vault"))
			notes.append("stage-9 stride at the tower: %s" % str(plan.get("reason", "ok")))
			_force("ability.colossus_stride"),
			{}, [[0.5, "stride_stage9_over_the_tower", {}], [1.7, "stride_stage9_landing_inside", {}]],
			func(_t: float) -> void: _view_set(_cam_at(810, -20, 34.0, 740, -100, 14.0, 60.0))],
		# only at stage 9: the rimkin by the Fallen King break at the sight of him
		["scatter", 10.0, func() -> void:
			_grow(9)
			_at(28, -1392, Vector3(40, 0, -1448)),
			{}, [[1.5, "rimkin_see_a_stage9_giant", {}], [9.0, "rimkin_break_and_flee", {}]],
			func(t: float) -> void:
				_view_set(_cam_at(-60, -1330, 55.0, 40, -1440, 4.0, 62.0))
				if t > 9.5 and t < 9.54:
					_note_rimkin()],
		# only at stage 9: the Fallen King's crown-iron, 35 m up on his standing shin
		["shin", 4.0, func() -> void:
			_hud(true)
			_at(64, -1386, Vector3(80.72, 0, -1397.99))
			_pickup(SHIN),
			{}, [[1.2, "fallen_kings_crown_iron_taken", {}]], func(_t: float) -> void: _view_set(_cam_at(20, -1340, 36.0, 80, -1398, 30.0, 58.0))],
		["shin_end", 0.5, func() -> void: _hud(false), {}, [], func(_t: float) -> void: pass],
	])
	# each titan weapon on the stage-9 body, front and back (open ground below the Rimstone's rise)
	for w: String in WEAPONS:
		var key := w.trim_prefix("weapon.")
		beats.append(["weapons_%s" % key, 2.6, func() -> void:
			_grow(9)
			_p.equipment.grant_weapon(w, true)
			_at(-40, -1290, Vector3(-40, 0, -1200)),
			{}, [[1.2, "stage9_%s_front" % key, {}], [2.4, "stage9_%s_back" % key, _cam_at(-58, -1366, 16.0, -40, -1290, 18.0, 50.0)]],
			func(t: float) -> void:
				if t < 1.3:
					_view_set(_cam_at(-22, -1214, 16.0, -40, -1290, 18.0, 50.0))])
	beats.append(["end", 1.0, func() -> void: _hud(false), {}, [], func(_t: float) -> void: pass])
	return beats


## The milestone D gate's look (--d3-beats=dgate): a stage-8 giant from the gameplay camera at the Stormstair's pools in
## the storm, at the Rimeglass's tarn frozen and thawed, then back at the Stormstair - its chunks loaded again after the
## Stormcaller's fall (the storm must be gone at once) - and its pools calm.
func _dgate_beats() -> Array:
	var game := {"game": true, "yaw_off": 0.0, "pitch": 14.0}
	var low := {"game": true, "yaw_off": 0.0, "pitch": 8.0}
	return [
		["dgate_storm_bellmere", 5.0, func() -> void:
			_grow(8)
			_at(-96, -330, Vector3(-100, 0, -392)),
			game, [[4.5, "dgate_pools_in_the_storm_bellmere", game]], null],
		["dgate_storm_lower", 4.0, func() -> void: _at(-95, -250, Vector3(-95, 0, -305)),
			low, [[3.5, "dgate_pools_in_the_storm_lower_pools", low]], null],
		["dgate_tarn_frozen", 4.0, func() -> void: _at(572, -1528, Vector3(636, 0, -1590)),
			game, [[3.5, "dgate_tarn_frozen", game]], null],
		["dgate_tarn_thawed", 12.0, func() -> void:
			# (both fallen, as a kill leaves them: the flags and the killed records; the Frostbound here hidden)
			WorldState.set_flag("boss.stormcaller.defeated", true)
			WorldState.set_flag("boss.frostbound.defeated", true)
			for id: String in ["world.hoarfell.frostbound", "world.drowned.stormcaller"]:
				WorldState.record_killed(id)
			for n in _p.get_tree().get_nodes_in_group("enemies"):
				if str(n.get("entity_id")) == "world.hoarfell.frostbound":
					(n as Node3D).visible = false,
			game, [[11.5, "dgate_tarn_thawed", game]], null],
		["dgate_storm_reloaded", 4.0, func() -> void: _at(-96, -330, Vector3(-100, 0, -392)),
			game, [[0.7, "dgate_stormstair_loaded_after_his_fall_0_7s", game], [3.5, "dgate_pools_calm_bellmere", game]],
			func(t: float) -> void:
				if t < 0.05:
					var w := _p.get_tree().get_first_node_in_group(StormWeather.GROUP) as StormWeather
					notes.append("storm reloaded after his fall: %s" % ("no weather node" if w == null else
						"clearing %.2f intensity %.2f" % [w.clearing, w.intensity]))],
		["dgate_calm_lower", 4.0, func() -> void: _at(-95, -250, Vector3(-95, 0, -305)),
			low, [[3.5, "dgate_pools_calm_lower_pools", low]], null],
	]


## The film (about 55 s): the growth 8 -> 9 at the Rimstone, the camera wheeling round as he swells, then he walks
## through Millford at stage 9, a chase camera behind him, past its houses and folk, and stops among them.
func _film_beats() -> Array:
	return [
		["film_before", 4.0, func() -> void:
			WorldState.set_flag("boss.frostbound.defeated", true)
			WorldState.set_flag("boss.stormcaller.defeated", true)
			_grow(8)
			_set_level(17)
			_at_rimstone(),
			{}, [[2.0, "film_before", {}]], func(t: float) -> void: _orbit(t, 0.0)],
		["film_growth", 10.0, func() -> void: _try_grow(9),
			{}, [[1.5, "film_during", {}], [8.0, "film_after", {}]], func(t: float) -> void: _orbit(4.0 + t, 0.0)],
		["film_eye", 4.0, func() -> void: pass,
			{"eye": true, "down": 10.0}, [[2.0, "film_giants_eye_at_the_rimstone", {"eye": true, "down": 10.0}]], null],
		["film_millford", 34.0, func() -> void:
			_at(-250, 560, Vector3(-420, 0, 660))
			_walk(Vector2(0, 1)),
			{}, [[4.0, "film_millford_start", {}], [17.0, "film_millford_mid", {}], [30.0, "film_millford_late", {}]],
			func(t: float) -> void:
				if t > 30.0:
					_walk(Vector2.ZERO)
				_chase(lerpf(46.0, 40.0, clampf(t / 30.0, 0.0, 1.0)), 6.0)],
		["film_end", 3.0, func() -> void: _walk(Vector2.ZERO),
			{"eye": true, "down": 22.0}, [[1.5, "film_millford_from_his_eyes", {"eye": true, "down": 22.0}]], null],
	]


## The camera wheeling round the Rimstone's giant over `t` seconds (a quarter turn in 14 s), low, looking up at him.
func _orbit(t: float, start_deg: float) -> void:
	var a := deg_to_rad(start_deg + 90.0 * clampf(t / 14.0, 0.0, 1.0))
	var c := _p.global_position
	var at := Vector3(c.x + sin(a) * 82.0, 0.0, c.z + cos(a) * 82.0)
	var g := _floor(at.x, at.z)
	_view_set({"at": Vector3(at.x, maxf(g.y, c.y) + 14.0, at.z), "look": c + Vector3.UP * 22.0, "fov": 58.0})
