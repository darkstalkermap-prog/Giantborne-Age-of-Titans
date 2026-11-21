class_name CaptureM11
extends CaptureM10
## The M11 capture tour, part A (P50; plan M11 §3.3 item 7, §2.13) and part B (P57: the wardrobe in play,
## part_b_beats()): --scenario=capture_m11 --part=a shows the
## giant's motion beat by beat and films each beat's moment from the side, the front and three-quarters
## (m11a_NN_<beat>_<view>.png under user://captures or --capture-dir=): the tree pauses at the moment, a camera
## of the tour's own stands at each view in turn (k times its stage-1 distance), and the game's camera comes
## back after. First-person beats are filmed through the game's own camera. Run it with a display and the
## skinned layers, and --write-movie for a video:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     -- --no-user-settings --scenario=capture_m11 --part=a --skin --capture-dir=<out>
##
## The beats: idle, walk, run, sprint, a turn each way on the spot, a jump and its landing; each family's light
## and heavy (the club, the sword, the hammer and the axe at stage 1; the tree at 3; the fists at 4); the stomp
## (lifted and planted), the roar, a self buff, a block, both dodges, Shoulder Charge, a grab, hold and throw;
## a flinch from each of four sides; stages 4 and 6 (walking), and an unreforged club's heavy at each (the reach
## past its fit stage); first person at rest, blocking and looking down; the death. The giant wears the
## long braided hair, the braided beard and the wayfarer's cape all along, so every chain of the secondary
## motion is on screen. Headless the tour still runs every beat and takes its measures (no frame is drawn):
## AUTOPILOT_RESULT's "capture_m11" has its shots, its notes (a beat the game refused), the legs' source at
## each moment, the flinches by side and the grip's measures over the generic poses (`grip`: the handle's line
## to the fist's centre, x k, and the fist's own axis off the handle).

## The default part; P57: --part=b is the wardrobe's (see part_b_beats()); P64b: --part=c the people's and the
## creatures' (see part_c_beats()).
const PART := "a"
const PARTS := ["a", "b", "c"]
const VIEWS := ["side", "front", "three_quarter"]
## The tour's camera at stage 1: its distance from the giant's middle, its height and where it looks (m).
const CAM_DISTANCE_M := 8.5
const CAM_HEIGHT_M := 2.2
const CAM_LOOK_M := 1.9
## The tour's look: the young giant's with the long braided hair, the braided beard and the wayfarer's cape.
const LOOK_PRESET := "appearance_preset.young_giant"
const LOOK_HAIR := "hair.long_braided"
const LOOK_BEARD := "beard.braided"
## The beats whose arm is the brain's generic mapping, where the handle must pass through the fist.
const GENERIC := ["idle", "stomp_lift", "stomp_plant", "roar", "self_buff", "fp_rest", "walk", "block"]

var _cam: Camera3D = null
var _views: Array = []          # the views still to film at this moment
var _shot_name := ""
var _rig: SkinnedRig = null
var _on_posed: Callable
var _moments: Array = []        # [fraction, ...] of the running beat still to come
## The measures (see the header).
var measures := {"legs": {}, "gait": {}, "flinch_sides": {}, "grip": {"handle_m": 0.0, "axis_deg": 0.0, "wrist_deg": 0.0, "frames": 0},
	"secondary": {"frames": 0, "worst_over_limit_deg": 0.0, "chains": []}, "reach": {"clavicle_m": 0.0, "lean_deg": 0.0, "pelvis_m": 0.0}}
var _beat_name := ""
var _open := Vector3.INF
var _open_yaw := 0.0


func _init(autopilot: Node) -> void:
	super._init(autopilot)
	# --capture-beats=a,b,...: only those beats (and the first, which dresses the giant): a quick look at a few
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-beats="):
			only = arg.substr(16)
	if only != "":
		var keep := only.split(",")
		var kept: Array = []
		for i in _beats.size():
			if i == 0 or keep.has(str(_beats[i][0])):
				kept.append(_beats[i])
		_beats = kept
		_names = PackedStringArray()
		for bt: Array in _beats:
			_names.append(str(bt[0]))


func dispose() -> void:
	super.dispose()
	_clear_c()
	if _rig != null and is_instance_valid(_rig) and _on_posed.is_valid() and _rig.posed.is_connected(_on_posed):
		_rig.posed.disconnect(_on_posed)
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


## One physics tick of the tour; true once it has ended.
func step(player: GiantPlayer, dt: float) -> bool:
	if done:
		return true
	_p = player
	_p.router.use_injection = true
	_hold_mouse()
	_watch_rig()
	if not _views.is_empty():
		_film_next_view()
		return false
	if _i < 0 or _t >= float(_beats[_i][1]):
		_i += 1
		_t = 0.0
		if _i >= _beats.size():
			done = true
			dispose()
			return true
		_release_inputs()
		_expect = ""
		_beat_name = str(_beats[_i][0])
		var at: Variant = _beats[_i][3]
		_moments = (at as Array).duplicate() if typeof(at) == TYPE_ARRAY else ([at] if float(at) >= 0.0 else [])
		var start: Callable = _beats[_i][2]
		start.call()
	_t += dt
	var tick: Variant = _beats[_i][4] if (_beats[_i] as Array).size() > 4 else null
	if tick is Callable:
		(tick as Callable).call(dt)
	if _expect != "" and _p.controller.action != null and _p.controller.action.id == _expect:
		_expect = ""
	if not _moments.is_empty() and _t >= float(_moments[0]) * float(_beats[_i][1]):
		var frac := float(_moments.pop_front())
		if _expect != "":
			notes.append("%s: %s was not cast by the shot" % [_beat_name, _expect])
			_expect = ""
		var label := _beat_name if (_beats[_i][3] is float) else "%s_%02d" % [_beat_name, int(round(frac * 100.0))]
		_moment(label)
	return false


## A moment of a beat: the legs' source noted, then the views filmed one a tick with the tree paused.
func _moment(label: String) -> void:
	if _rig != null:
		var w := _rig.blend_weights()
		measures.legs[label] = _rig.legs_source()
		measures.gait[label] = {"move": snappedf(float(w.move), 0.01), "run": snappedf(float(w.run), 0.01),
			"sprint": snappedf(float(w.sprint), 0.01)}
	_shot_name = "m11%s_%02d_%s" % [part(), _i + 1, label]
	var fp := _p.camera_rig.is_first_person()
	_views = ["game"] if fp else VIEWS.duplicate()
	if _subject != null and is_instance_valid(_subject):
		_views.push_front("game")   # part C: the game's own camera first, then the subject from the tour's views
	_views.append("restore")
	_p.get_tree().paused = true
	_film_next_view()


func _film_next_view() -> void:
	var view: String = _views.pop_front()
	if view == "restore":
		# a tick after the last view's frame was drawn: the game's camera back, the tree running
		if _cam != null:
			_cam.current = false
		if _p.camera_rig != null and _p.camera_rig.camera != null:
			_p.camera_rig.camera.make_current()
		_p.get_tree().paused = false
		return
	if view != "game":
		_place_camera(view)
	var name := "%s_%s.png" % [_shot_name, view]
	if _auto != null and _auto.has_method("_shot"):
		_auto.call("_shot", name)
	shots.append(name)


## The tour's camera at `view` round the giant (his own frame: the side is his right), k times its stage-1
## distance.
func _place_camera(view: String) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.name = "CaptureM11Camera"
		_cam.fov = 50.0
		_cam.far = 4000.0
		_p.get_tree().root.add_child(_cam)
	var k := maxf(_p.rig.body_scale, 0.01)
	var basis := _p.global_transform.basis.orthonormalized()
	var dir := {"side": basis.x, "front": -basis.z, "three_quarter": (basis.x - basis.z).normalized()}[view] as Vector3
	var look := _p.global_position + Vector3.UP * CAM_LOOK_M * k
	var want := _p.global_position + dir * CAM_DISTANCE_M * k + Vector3.UP * CAM_HEIGHT_M * k
	if _subject != null and is_instance_valid(_subject):
		# part C: round the subject in its own frame, at a distance for its height (SUBJECT_DISTANCE x, at least 3 m)
		var sb := _subject.global_transform.basis.orthonormalized()
		var sdir := {"side": sb.x, "front": -sb.z, "three_quarter": (sb.x - sb.z).normalized()}[view] as Vector3
		look = _subject.global_position + Vector3.UP * _subject_h * 0.55
		want = _subject.global_position + sdir * maxf(3.0, _subject_h * SUBJECT_DISTANCE) + Vector3.UP * _subject_h * 0.65
	# a wall between the giant and the camera: the camera comes in front of it, as a spring arm does
	var q := PhysicsRayQueryParameters3D.create(look, want)
	q.exclude = [_p.get_rid()] if _subject == null or not (_subject is CollisionObject3D) else [_p.get_rid(), (_subject as CollisionObject3D).get_rid()]
	var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit.position as Vector3) + (look - want).normalized() * 0.3
	_cam.global_position = want
	_cam.look_at(look, Vector3.UP)
	_cam.make_current()


## Puts the giant on open ground facing open ground (the arena's walls and props out of the way of the moving
## beats and the cameras), found once by rays round where he started.
func _to_open_ground() -> void:
	if _open == Vector3.INF:
		_open = _find_open()
	_p.global_position = _open
	_p.velocity = Vector3.ZERO
	_p.facing_yaw = _open_yaw
	_p.rotation.y = _open_yaw
	_view(0.0, -12.0)


## The most open place within 180 m of the start: the one whose nearest obstacle (eight rays at the knee and
## the head) is farthest, with room ahead for the sprint; the giant faces its longest ray.
func _find_open() -> Vector3:
	var space := _p.get_world_3d().direct_space_state
	var origin := _p.global_position
	var ex := [_p.get_rid()]
	var best := origin
	var best_score := -1.0
	for r: float in [0.0, 20.0, 40.0, 60.0, 80.0, 110.0, 140.0, 180.0]:
		for a in range(0, 360, 30 if r > 0.0 else 360):
			var c := origin + Vector3(cos(deg_to_rad(a)), 0.0, sin(deg_to_rad(a))) * r
			var fq := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 40.0, c + Vector3.DOWN * 40.0)
			fq.exclude = ex
			var floor_hit := space.intersect_ray(fq)
			if floor_hit.is_empty() or absf((floor_hit.position as Vector3).y - origin.y) > 4.0:
				continue
			var g: Vector3 = floor_hit.position
			var nearest := INF
			var longest := 0.0
			var yaw := 0.0
			for d in range(0, 360, 45):
				var dir := Vector3(-sin(deg_to_rad(d)), 0.0, -cos(deg_to_rad(d)))   # yaw d's forward
				var free := 60.0
				for h: float in [1.0, 4.0]:
					var rq := PhysicsRayQueryParameters3D.create(g + Vector3.UP * h, g + Vector3.UP * h + dir * 60.0)
					rq.exclude = ex
					var hit := space.intersect_ray(rq)
					if not hit.is_empty():
						free = minf(free, (hit.position as Vector3).distance_to(g + Vector3.UP * h))
				nearest = minf(nearest, free)
				if free > longest:
					longest = free
					yaw = deg_to_rad(d)
			var score := minf(nearest, 25.0) + 0.5 * longest
			if score > best_score:
				best_score = score
				best = g
				_open_yaw = yaw
	if best_score < 20.0:
		notes.append("open ground: the best place has %.1f of room" % best_score)
	return best + Vector3.UP * 0.05


## The measures, taken in the rig's `posed` (final bones): the grip over the generic poses, the secondary
## motion's limits, the reach extension.
func _watch_rig() -> void:
	var rig := _p.rig as SkinnedRig
	if rig == _rig:
		return
	if _rig != null and is_instance_valid(_rig) and _on_posed.is_valid() and _rig.posed.is_connected(_on_posed):
		_rig.posed.disconnect(_on_posed)
	_rig = rig
	if _rig == null:
		return
	_on_posed = _measure
	_rig.posed.connect(_on_posed)


func _measure() -> void:
	if _rig == null or _rig.modifier() == null:
		return
	var mod := _rig.modifier()
	var k := maxf(_rig.body_scale, 0.01)
	if _beat_name in GENERIC and _p.controller.state != CombatController.State.DEAD:
		var f := mod.fist("r")
		var socket := _rig.weapon_socket()
		if not f.is_empty() and socket != null:
			var centre := _rig.body.global_transform * (f.centre as Vector3)
			var a := socket.global_position
			var b := a - socket.global_transform.basis.z.normalized()
			var g: Dictionary = measures.grip
			var off := centre.distance_to(Geometry3D.get_closest_point_to_segment_uncapped(centre, a, b)) / k
			g.handle_m = maxf(float(g.handle_m), off)
			g.axis_deg = maxf(float(g.axis_deg), float(mod.stats.get("grip_axis_deg", 0.0)))
			g.wrist_deg = maxf(float(g.wrist_deg), float(mod.stats.get("wrist_deg", 0.0)))
			g.frames = int(g.frames) + 1
	var sm := _rig.secondary()
	if sm != null and not sm.chains.is_empty():
		var s: Dictionary = measures.secondary
		s.frames = int(s.frames) + 1
		s.chains = Array(sm.chains)
		var limits := sm.joint_limits()
		var angles := sm.joint_angles()
		for bone: String in angles:
			var ang: Array = angles[bone]
			s.worst_over_limit_deg = maxf(float(s.worst_over_limit_deg), float(ang[0]) - float(limits.get(bone, 90.0)))
	for key: String in measures.reach:
		measures.reach[key] = maxf(float(measures.reach[key]), float(mod.reach_ext.get(key, 0.0)))


## The tour's look (the header): every chain of the secondary motion on screen.
func _wear_the_look() -> void:
	var rec := Appearance.preset_record(LOOK_PRESET)
	if rec.is_empty():
		notes.append("look: %s missing" % LOOK_PRESET)
		return
	rec = rec.duplicate(true)
	rec["hair"]["style"] = LOOK_HAIR
	rec["beard"]["style"] = LOOK_BEARD
	_p.appearance.set_record(rec)


## A synthetic hit from `local` (the attacker's place in the giant's own frame), as the M10 tour's hits.
func _hit_from(local: Vector3, power: float) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "capture"
	e.target_id = _p.entity.entity_id
	e.power = power
	e.attacker_stat = 10.0
	e.attacker_height_m = 1.8
	e.damage_split = {"physical": 1.0}
	e.poise_damage = 0.0
	e.tags = PackedStringArray(["Melee", "Unblockable"])
	e.attacker_position = _p.global_transform * local
	Sim.queue_hit(e)


func _flinch_beat(side: String) -> Array:
	var local := {"f": Vector3(0, 0, -3), "b": Vector3(0, 0, 3), "l": Vector3(-3, 0, 0), "r": Vector3(3, 0, 0)}[side] as Vector3
	var before := [0]
	return ["flinch_" + side, 0.8, func() -> void:
		var pools := _p.entity.combatant.pools
		pools.health = pools.health_max
		before[0] = int(_p.rig.get("flinches"))
		measures.flinch_sides[side] = false
		_hit_from(local * _p.rig.body_scale, 1.0), 0.17,
		func(_dt: float) -> void:
			if int(_p.rig.get("flinches")) > before[0]:
				measures.flinch_sides[side] = true]


## The part the command line asks for (--part=a, b or c; "a" without one, "" for a part this build does not have).
static func part() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--part="):
			var p := arg.substr(7)
			return p if p in PARTS else ""
	return PART


## P57 (plan M11 §3.10 item 6): part B, the wardrobe in play - the giant in the world's light at the game's own
## cameras: every preset standing (the tour's three views), the fullest look standing, walking, running, at stage 4
## and in first person, and the build sliders at the creator's ends from the three views. Frames m11b_NN_<beat>_<view>.
func part_b_beats() -> Array:
	var b: Array = []
	var dress := func(rec: Dictionary) -> void:
		_p.appearance.set_record(rec)
		_to_open_ground()
	for pid in Appearance.preset_ids():
		var rec := Appearance.preset_record(pid)
		b.append(["preset_" + pid.get_slice(".", 1), 1.2, func() -> void: dress.call(rec), 0.8])
	var base := Appearance.preset_record("appearance_preset.wanderer")
	var fullest := _fullest(base)
	b.append(["fullest", 1.2, func() -> void: dress.call(fullest), 0.8])
	b.append(["fullest_walk", 2.0, func() -> void:
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 0.55)), 0.8])
	b.append(["fullest_run", 2.0, func() -> void:
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 1.0)), 0.8])
	b.append(["fullest_stage_4", 2.0, func() -> void:
		_stage(4)
		_to_open_ground(), 0.8])
	b.append(["fullest_fp", 1.6, func() -> void:
		_stage(1)
		_equip("weapon.club")
		_p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
		_view(0.0, -30.0), 0.8])
	b.append(["fullest_fp_down", 1.4, func() -> void: _view(0.0, -70.0), 0.7])
	for o: Dictionary in Appearance.options("build", ""):
		for v: float in [-OptionRows.BUILD_LIMIT, OptionRows.BUILD_LIMIT]:
			var rec := OptionRows.with_value(fullest, "build." + str(o.key), v)
			b.append(["build_%s_%s" % [str(o.key), "low" if v < 0.0 else "high"], 1.2, func() -> void:
				_p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)
				dress.call(rec), 0.8])
	return b


## The fullest look of the data: the outfit that fills the most slots and an accessory in every accessory slot.
static func _fullest(base: Dictionary) -> Dictionary:
	var best := ""
	var most := -1
	for id in Appearance.option_ids("outfit"):
		var n := Appearance.record_garments(Appearance.with_outfit(base, id)).size()
		if n > most:
			most = n
			best = id
	var rec := Appearance.with_outfit(base, best) if best != "" else base.duplicate(true)
	for slot: String in Appearance.ACCESSORY_SLOTS:
		for id in Appearance.option_ids("accessory"):
			if str(Appearance.option(id).get("slot", "")) == slot:
				rec = OptionRows.with_value(rec, "outfit.accessories." + slot, id)
				break
	return rec


# --------------------------------------------------------------------------- part C (P64b)

## Part C's subjects stand back this many times their height for the tour's views.
const SUBJECT_DISTANCE := 1.9
const VILLAGER := "res://scenes/npcs/villager.tscn"
const CAVALRY := "res://scenes/enemies/cavalry.tscn"
const WOLF := "res://scenes/enemies/wolf.tscn"
const DIRE_WOLF := "res://scenes/enemies/dire_wolf.tscn"

var _subject: Node3D = null
var _subject_h := 1.8
var _spawned: Array = []
var _carry: Array = []          # [actor, velocity (world)] moved by the tour every tick


## P64b (plan M11 §3.17 design 5): part C, the people and the creatures in play beside the stage-1 giant - the
## town (villagers about him), the cavalry (a gallop past, the charge's couched lance, the rider's fall from a
## dead horse), the brutes (the ogre's sweep and smash, the troll's club, the whelp's swipe), the bosses (the
## Ogre King's combo, backhand and slam, the Troll Matriarch's sweep, frenzy and whelp throw) and the wolves (a
## pack trotting past, a wolf's lunge). Each moment is filmed through the game's own camera and from the side,
## the front and three-quarters of its subject. Frames m11c_NN_<beat>_<view>. The actors' AI is off: the tour
## asks for each attack itself, and the giant is healed every tick.
func part_c_beats() -> Array:
	var b: Array = []
	b.append(["c_start", 0.6, func() -> void:
		_to_open_ground()
		_view(0.0, -10.0), -1.0, _heal])
	b.append(["town", 3.0, func() -> void:
		_clear_c()
		for i in 5:
			var e := _spawn_c(VILLAGER, "capture.villager_%d" % i, 7.0 + float(i % 3) * 1.5, (float(i) - 2.0) * 2.2, true)
			if i == 2:
				_set_subject(e, 1.8)
		, [0.5, 0.9], _heal])
	b.append(["cavalry_gallop", 2.6, func() -> void:
		_clear_c()
		var c := _spawn_c(CAVALRY, "capture.cavalry", 12.0, -20.0, false)
		_turn_to(c, _right())
		_carry.append([c, _right() * 13.0])
		_set_subject(c, 2.6), [0.55, 0.72], _tick_c])
	b.append(["cavalry_charge", 2.4, func() -> void:
		_clear_c()
		var c := _spawn_c(CAVALRY, "capture.cavalry_charge", 22.0, 0.0, true)
		_set_subject(c, 2.6)
		_attack(c, "ability.cavalry_charge"), [0.3], _heal])
	b.append(["rider_fall", 3.0, func() -> void:
		_clear_c()
		var c := _spawn_c(CAVALRY, "capture.cavalry_fall", 10.0, 3.0, false)
		_turn_to(c, _right())
		_set_subject(c, 2.6)
		(c.get("controller") as CombatController).kill(), [0.2, 0.4, 0.6, 0.9], _heal])
	for spec: Array in [["ogre_sweep", "res://scenes/enemies/ogre.tscn", "ability.ogre_sweep", 3.4],
			["ogre_smash", "res://scenes/enemies/ogre.tscn", "ability.ogre_smash", 3.4],
			["troll_club", "res://scenes/enemies/troll.tscn", "ability.troll_club", 5.5],
			["whelp_swipe", "res://scenes/enemies/troll_whelp.tscn", "ability.troll_whelp_swipe", 3.5],
			["king_combo", "res://scenes/enemies/ogre_king.tscn", "ability.boss_combo_1", 8.5],
			["king_backhand", "res://scenes/enemies/ogre_king.tscn", "ability.boss_combo_2", 8.5],
			["king_slam", "res://scenes/enemies/ogre_king.tscn", "ability.boss_slam", 8.5],
			["matriarch_sweep", "res://scenes/enemies/troll_matriarch.tscn", "ability.matriarch_sweep", 9.0],
			["matriarch_frenzy", "res://scenes/enemies/troll_matriarch.tscn", "ability.matriarch_frenzy_1", 9.0],
			["matriarch_whelp_throw", "res://scenes/enemies/troll_matriarch.tscn", "ability.troll_throw_whelp", 9.0]]:
		b.append(_brute_beat(spec[0], spec[1], spec[2], spec[3]))
	b.append(["wolves_trot", 2.4, func() -> void:
		_clear_c()
		for i in 4:
			var w := _spawn_c(WOLF, "capture.wolf_%d" % i, 9.0 + float(i % 2) * 1.6, -9.0 - float(i) * 1.8, false)
			_turn_to(w, _right())
			_carry.append([w, _right() * 3.2])
			if i == 1:
				_set_subject(w, 0.9)
		var d := _spawn_c(DIRE_WOLF, "capture.dire_wolf", 12.0, -11.0, false)
		_turn_to(d, _right())
		_carry.append([d, _right() * 3.2]), [0.6, 0.9], _tick_c])
	b.append(["wolves_gallop", 1.8, func() -> void:
		for c: Array in _carry:
			c[1] = (c[1] as Vector3).normalized() * 8.5, [0.7], _tick_c])
	b.append(["wolf_lunge", 2.4, func() -> void:
		_clear_c()
		var w := _spawn_c(WOLF, "capture.wolf_lunge", 9.0, 3.0, true)
		_set_subject(w, 0.9)
		_attack(w, "ability.wolf_lunge"), [0.25, 0.45], _heal])
	b.append(["c_end", 0.4, func() -> void: _clear_c(), -1.0])
	return b


## A brute's or a boss's attack, filmed at its windup's end and in its active phase.
func _brute_beat(label: String, scene: String, action: String, h: float) -> Array:
	var a := GameData.get_action(action)
	var windup := float(a.windup_ticks) / Sim.TICK_RATE if a != null else 1.0
	var active := float(a.active_ticks) / Sim.TICK_RATE if a != null else 0.2
	var seconds := 0.3 + windup + active + 1.0
	return [label, seconds, func() -> void:
		_clear_c()
		var e := _spawn_c(scene, "capture." + label, maxf(7.0, h * 1.25), maxf(1.5, h * 0.25), true)
		if action == "ability.troll_throw_whelp":
			_spawn_c("res://scenes/enemies/troll_whelp.tscn", "capture.whelp", maxf(7.0, h * 1.25) - 1.0, -4.0, true)
		_set_subject(e, h)
		_attack(e, action), [(0.3 + windup * 0.9) / seconds, (0.3 + windup + active * 0.6) / seconds], _heal]


func _set_subject(e: Node3D, h: float) -> void:
	_subject = e
	_subject_h = h


func _right() -> Vector3:
	var x := _p.global_transform.basis.x
	return Vector3(x.x, 0.0, x.z).normalized()


## An actor `ahead` m before the giant and `side` m to his right, its AI off, facing him (`face`) or as placed.
func _spawn_c(scene: String, id: String, ahead: float, side: float, face: bool) -> Node3D:
	var e := (load(scene) as PackedScene).instantiate() as Node3D
	e.set("entity_id", id)
	e.set("ai_enabled", false)
	var fwd := -_p.global_transform.basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var pos := _p.global_position + fwd * ahead + _right() * side
	_p.get_parent().add_child(e)
	e.global_position = pos
	if face:
		_turn_to(e, (_p.global_position - pos))
	_spawned.append(e)
	return e


## Turns an actor to face along `dir` (its front is -Z).
func _turn_to(e: Node3D, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	e.rotation.y = atan2(-d.x, -d.z)
	if "facing_yaw" in e:
		e.set("facing_yaw", e.rotation.y)


func _attack(e: Node3D, action: String) -> void:
	var c := e.get("controller") as CombatController
	if c == null:
		notes.append("%s: no controller" % action)
		return
	if not (c.library as Dictionary).has(action):
		c.add_action(GameData.get_action(action))
	if c.request(&"attack", {"action_id": action}) != CombatController.Verdict.ACCEPT:
		notes.append("%s refused" % action)


## The giant healed every tick (the actors' attacks land on him).
func _heal(_dt := 0.0) -> void:
	var pools := _p.entity.combatant.pools
	pools.health = pools.health_max


## The carried actors moved on (their rigs read the motion) and the giant healed.
func _tick_c(dt: float) -> void:
	_heal()
	for c: Array in _carry:
		var e := c[0] as Node3D
		if is_instance_valid(e):
			e.global_position += (c[1] as Vector3) * dt
			e.set("velocity", c[1])


func _clear_c() -> void:
	_carry.clear()
	_subject = null
	for e: Variant in _spawned:
		if is_instance_valid(e):
			var n := e as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_spawned.clear()


## [label, seconds, start, shot at this share of the beat (-1: none; an Array: several moments), per tick]
func _make_beats() -> Array:
	if part() == "b":
		return part_b_beats()
	if part() == "c":
		return part_c_beats()
	var b: Array = []
	b.append(["idle", 2.0, func() -> void:
		_wear_the_look()
		_to_open_ground(), 0.8])
	b.append(["walk", 2.0, func() -> void:
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 0.55)), 0.8])
	b.append(["run", 2.0, func() -> void:
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 1.0)), 0.8])
	b.append(["sprint", 2.5, func() -> void:
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 1.0))
		_p.router.set_injected_hold(&"sprint", true), 0.8])
	b.append(["stop", 1.6, func() -> void: pass, [0.25, 0.9]])
	for side: Array in [["turn_left", 1.0], ["turn_right", -1.0]]:
		var sign: float = side[1]
		b.append([side[0], 1.6, func() -> void: pass, [0.3, 0.6], func(dt: float) -> void:
			if _t < 1.2:
				_p.facing_yaw = wrapf(_p.facing_yaw + sign * deg_to_rad(150.0) * dt, -PI, PI)])
	b.append(["jump", 2.2, func() -> void: _p.router.inject_edge(&"jump"), 0.12, func(_dt: float) -> void:
		if not _moments_taken("land") and _rig != null and _rig.legs_source() == "landing":
			_moment("land")])
	for w: Array in [["club", "weapon.club"], ["sword", "weapon.sword"], ["hammer", "weapon.hammer"], ["axe", "weapon.axe"]]:
		var id: String = w[1]
		b.append(["%s_light" % w[0], 1.4, func() -> void:
			if id == "weapon.club":
				_to_open_ground()
			_equip(id)
			_light(), 0.3])
		b.append(["%s_heavy" % w[0], 2.2, func() -> void: _heavy(), [0.25, 0.45]])
	b.append(["stomp", 2.0, func() -> void:
		_equip("weapon.club")
		_cast("ability.heavy_footfall"), [0.08, 0.14, 0.25]])
	b.append(["roar", 2.0, func() -> void: _cast("ability.thunder_roar"), 0.3])
	b.append(["self_buff", 2.0, func() -> void: _cast("ability.stone_skin"), 0.3])
	b.append(["block", 1.5, func() -> void:
		_p.router.set_injected_hold(&"block", true)
		_p.router.inject_edge(&"block_press"), 0.6])
	b.append(["dodge_roll", 1.4, func() -> void:
		_p.router.inject_edge(&"block_release")
		_p.router.set_injected_move(Vector2(1.0, 0.0))
		_p.router.inject_edge(&"dodge"), 0.25])
	b.append(["dodge_sidestep", 1.4, func() -> void:
		_p.router.set_injected_move(Vector2(-1.0, 0.0))
		_p.router.inject_edge(&"dodge"), 0.25])
	b.append(["shoulder_charge", 2.0, func() -> void: _cast("ability.shoulder_charge"), [0.15, 0.3]])
	b.append(["grab", 2.5, func() -> void:
		var s := _soldier()
		if s == null:
			notes.append("grab: no soldier")
			return
		_p.global_position = s.global_position + (s.global_transform.basis.z * 2.4)
		_p.look_at(s.global_position, Vector3.UP)
		_p.facing_yaw = _p.rotation.y
		s.entity.stagger(3.0, "capture")
		_p.grab.hold_timeout_s = 30.0
		if _p.grab.try_grab() != CombatController.Verdict.ACCEPT:
			notes.append("grab refused"), 0.8])
	b.append(["hold", 1.6, func() -> void: pass, 0.5])
	b.append(["throw", 2.0, func() -> void: _throw(), 0.3])
	b.append(["after_throw", 1.0, func() -> void:
		_clear_soldiers()
		_to_open_ground(), -1.0])
	for side: String in ["f", "b", "l", "r"]:
		b.append(_flinch_beat(side))
	b.append(["stage_4", 2.4, func() -> void:
		_stage(4)
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 0.5)), 0.85])
	b.append(["fists_light", 1.4, func() -> void:
		_equip("weapon.fists")
		_light(), 0.3])
	b.append(["fists_heavy", 2.2, func() -> void: _heavy(), 0.45])
	b.append(["club_past_fit_4", 2.2, func() -> void:
		_equip("weapon.club")
		_to_open_ground()
		_heavy(), [0.3, 0.45]])
	b.append(["stage_3_tree", 2.0, func() -> void:
		_stage(3)
		_equip("weapon.tree_oak")
		_light(), 0.4])
	b.append(["tree_heavy", 2.4, func() -> void: _heavy(), 0.45])
	b.append(["stage_6", 2.4, func() -> void:
		_stage(6)
		_equip("weapon.club")
		_to_open_ground()
		_p.router.set_injected_move(Vector2(0.0, 0.5)), 0.85])
	b.append(["club_past_fit_6", 2.2, func() -> void: _heavy(), [0.3, 0.45]])
	b.append(["fp_rest", 1.6, func() -> void:
		_stage(1)
		_equip("weapon.club")
		_p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
		_view(0.0, -10.0), 0.8])
	b.append(["fp_block", 1.4, func() -> void:
		_p.router.set_injected_hold(&"block", true)
		_p.router.inject_edge(&"block_press"), 0.6])
	b.append(["fp_down", 1.6, func() -> void:
		_p.router.inject_edge(&"block_release")
		_p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
		_view(0.0, -85.0), 0.7])
	b.append(["fp_down_60", 1.2, func() -> void: _view(0.0, -60.0), 0.7])
	b.append(["death", 3.0, func() -> void:
		_p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)
		_hit_self(50000.0), [0.3, 0.85]])
	return b


## True once a moment of the running beat named `label` was filmed.
func _moments_taken(label: String) -> bool:
	return measures.legs.has(label)
