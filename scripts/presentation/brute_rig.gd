class_name BruteRig
extends ActorRig
## The ogre, the troll, the whelp, the Ogre King and the Troll Matriarch skinned in play (P64; plan M11 §2.10, §3.17
## design 1). The pose brain stays: this is an ActorRig, whose _process poses the box rig's pivots (Body, its hips,
## torso and shoulders) from the actor's state on the frame clock as before, counts the footfalls and keeps the
## flash and the status tint. Where the people are drawn (PersonRig.layers_enabled(): a display, --skin,
## enable_for_tests(); never with --no-skin) and the record's `body.rig` is not "box", the box rig's meshes hide and
## the creature shows:
##
##   Visual (BruteRig)
##   └ Body                       leans, staggers and is carried in a fist as the brain says (ActorRig)
##     ├ (the box rig's pivots and merged meshes, hidden)
##     ├ Model                    the creature's glTF (assets/creatures: <creature>.glb), turned 180 degrees and scaled
##     │ └ <kind>_rig_001         from its file's height to the record's height_m
##     │   ├ Skeleton3D           23 bones: the clips (<creature>_clips.glb) and the arms' solve
##     │   │ ├ <variant>          the body (person.gdshader on the creature's atlas: the hide, the moss)
##     │   │ └ <outfit>_gear      the bosses' gear (the King's mantle, belt and crown; the Matriarch's mantle and
##     │   │                      bone crown), skinned to the same bones, in the same material
##     │   └ AnimationPlayer      manual: seeked from the brain's state
##     ├ WeaponSocket/Club        the club in the right fist (a gnarled limb; the King's banded in gold)
##     └ Far                      the variant's far mesh (no slot: see CreatureSlots), hidden while skinned
##
## The clip from the brain's state, cross-faded over FADE_S on a change:
##   walking or running  `walk` or `run` (above the record's mean of walk and run speed) on the distance walked: one
##                       turn of the clip a stride of the clip (the manifest's gait stride x the model's scale), so a
##                       planted foot does not slide at any speed; the King's charge runs the same way;
##   cylinder pulse      (the smash, the slam, the stomp) `slam`, its time from the action's phase: the windup raises
##                       both fists over the head (the clip to SLAM_TOP_S), the active phase brings them down to the
##                       ground in front (to SLAM_HIT_S), the recovery stands up; the box rig's timing exactly;
##   roar                (a phase's roar: hit shape none, or a pulse of morale; the King's charge's windup) `roar` the
##                       same way (to ROAR_TOP_S over the windup, held through the active phase);
##   the sweeps          (every sector pulse: the sweeps, the combos, the frenzy, the whelp's swipe; P64b) `brace`'s
##                       wide stance and the club swung two-handed on the action's clock (SWEEP_KEYS: drawn back high
##                       over the shoulder, across at the chest, round and down; a second blow the backhand);
##   other attacks       (the whelp throw) `brace` and the arms put where the brain's arm poses point by PersonRig's
##                       two-bone solve (the torso's twist on the spine), weighted in over 1 / ARM_RATE seconds;
##   a block or a guard  `brace`; held in a giant's fist: `brace`, the arms pushing at the fist (HELD_POSE, shaking);
##   dead                `death` on its own clock (the body stays upright: the clip falls); else `idle`.
## Draw calls: the body, the gear (the bosses), the club; one shadow draw a cascade for the body.
##
## The slots: at most CreatureSlots.MAX_SKINNED brutes and wolves are skinned at once (the bosses always); a brute
## without a slot shows its far mesh; one farther from the camera than its record's render_lod_m too (the bosses'
## records set none). A corpse that loses its slot keeps its last pose, unanimated. AI LOD tier 2 (dormant):
## Visual/LodProxy shows the far mesh. Headless, with --no-skin, or with `body.rig` "box", the box rig draws as before.
##
## Presentation only: this rig writes under its own Visual node and reads the actor; nothing in the simulation reads
## it (plan M10 §2.7).

const MANIFEST := "res://assets/creatures/manifest.json"
const MODEL_NAME := "Model"
const FAR_NAME := "Far"
const SOCKET_NAME := "WeaponSocket"
const LIBRARY := &"brute"
const GROUP := "brute_rigs"
const FADE_S := 0.2
const ARM_RATE := 10.0
## The slam clip's keys (seconds; P63's clip): the fists over the head, the fists on the ground in front.
const SLAM_TOP_S := 0.55
const SLAM_HIT_S := 0.8
## The roar clip's peak (seconds): its arms wide, its chest up.
const ROAR_TOP_S := 0.35
const ROAR_HOLD_S := 0.6
## The box rig's club is this long at the ogre's 3.4 m (heavy.gd's 1.6 m x the body plan's scale).
const CLUB_M_AT_OGRE := 1.6
const OGRE_H := 3.4
## The fist's centre and the handle's line in the hand bone's frame, as a person's (PersonRig.FIST_*), scaled by the
## creature's forearm against a person's (HUMAN_FOREARM_M).
const HUMAN_FOREARM_M := 0.26
## The club's line in the hand bone's frame: along the hand (+Y, wrist to knuckles), tipped a little toward the thumb
## and out of the palm, so a hanging arm carries it head down by the leg and a raised arm holds it up.
const CLUB_AXIS := Vector3(0.3, 1.0, 0.12)
## The arms pushing at the giant's fist while held (yaw, pitch in degrees, as the brain's poses), shaking.
const HELD_POSE := Vector2(40.0, 35.0)
## The palettes when the record sets none (skin: the hide; hair: the brows and marks; cloth: the loincloth;
## faction: the King's mantle).
const PALETTES := {
	"ogre": {"skin": "#80885c", "hair": "#29201a", "cloth": "#6b4f33", "faction": "#751a21"},
	"troll": {"skin": "#6b7a66", "hair": "#4d6b2e", "cloth": "#544530", "faction": "#665033"},
}

static var _index: Dictionary = {}
static var _facts: Dictionary = {}
static var _libs: Dictionary = {}       # creature -> AnimationLibrary (the tracks retargeted to "Skeleton3D:<bone>")
static var _clubs: Dictionary = {}      # "plain" | "banded" -> ArrayMesh

## The record's `body` decision: -1 undecided (the actor reads its record after this rig is ready), 0 box, 1 skinned.
var _mode := -1
var skinned := false
var _pending_lod := 0.0
var _creature := ""
var _variant := ""
var _outfit := ""
var _boss := false
var _scale := 1.0
var _model: Node3D = null
var _sk: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _gear: MeshInstance3D = null
var _far: MeshInstance3D = null
var _socket: Node3D = null
var _club: MeshInstance3D = null
var _material: ShaderMaterial = null
var _club_material: ShaderMaterial = null
var _player: AnimationPlayer = null
var _bones := {}
var _fist := Vector3(0.0, 0.075, 0.0)
var _clip := ""
var _clip_t := 0.0
var _gait := 0.0            # the walk's and the run's clip turns (distance over the clip's stride)
var _stride := {"walk": 3.0, "run": 3.0}
var _run_from := 3.3
var _dead_t := -1.0
var _w_arm := 0.0
var _w_off := 0.0
var _reach := 1.0
var _slot := false
var _frozen := false
var _slot_applied := false
var _time := 0.0
var _death_len := -1.0
var _half_skip := false
var _half_dt := 0.0
var _height := OGRE_H
## Frames posed skinned (tests, stats).
var skinned_frames := 0


# --------------------------------------------------------------------------- setup

func _enter_tree() -> void:
	CreatureSlots.register(self)
	add_to_group(GROUP)


func _exit_tree() -> void:
	CreatureSlots.unregister(self)


## The creatures' manifest: its index (the scenes, the maps, the gear and the variants) and the kinds' facts.
static func creature_index() -> Dictionary:
	if _index.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
		if doc is Dictionary:
			_index = (doc as Dictionary).get("index", {})
			_facts = doc
	return _index


## The distance LOD: the box rig takes it as before; skinned, render_lod_m is where the far mesh takes over.
func set_render_lod(lod_m: float) -> void:
	_pending_lod = maxf(0.0, lod_m)
	if _mode == 1:
		render_lod_m = _pending_lod
	else:
		super.set_render_lod(lod_m)


## The record's `body` (creature, variant, outfit, palette; `rig` "box" keeps the box rig) and the switch.
func _decide() -> void:
	var rec: Variant = actor.get("record") if actor != null and "record" in actor else null
	if typeof(rec) != TYPE_DICTIONARY or (rec as Dictionary).is_empty():
		return   # the record is not read yet
	var record: Dictionary = rec
	var body_key: Dictionary = record.get("body", {}) if typeof(record.get("body")) == TYPE_DICTIONARY else {}
	var want := str(body_key.get("rig", "skinned")) != "box" and body_key.has("creature")
	_mode = 1 if want and PersonRig.layers_enabled() and _build(record, body_key) else 0
	skinned = _mode == 1
	if not skinned:
		return
	RigPaint.apply_render_lod(self, body, 0.0)
	far_proxy = null
	if mid_proxy != null:
		RigPaint.remove_mid_lod(body, render_lod_m)
		mid_proxy = null
	render_lod_m = _pending_lod
	for c in body.get_children():
		if c == _model or c == _socket or c == _far:
			continue
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false
		elif c is Node3D:
			for g in (c as Node3D).find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).visible = false
	_fill_lod_proxy()


func _build(record: Dictionary, body_key: Dictionary) -> bool:
	_creature = str(body_key.get("creature", ""))
	var entry: Dictionary = creature_index().get(_creature, {})
	if entry.is_empty() or not ResourceLoader.exists(str(entry.get("scene", ""))):
		return false
	var variants: Dictionary = entry.get("variants", {})
	_variant = str(body_key.get("variant", ""))
	if not variants.has(_variant):
		_variant = str(variants.keys()[0]) if not variants.is_empty() else ""
	var v: Dictionary = variants.get(_variant, {})
	_outfit = str(body_key.get("outfit", ""))
	_boss = (record.get("boss", null) is Dictionary)
	var file_h := float(v.get("game_height_m", OGRE_H)) / maxf(float(v.get("game_scale", 1.0)), 1e-3)
	_height = float(record.get("height_m", file_h))
	_scale = _height / maxf(file_h, 1e-3)
	_model = (load(str(entry.scene)) as PackedScene).instantiate() as Node3D
	_model.name = MODEL_NAME
	body.add_child(_model)
	_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * _scale), Vector3.ZERO)
	var far_name := str(v.get("far", _variant + "_far"))
	var gear_name := str(((entry.get("gear", {}) as Dictionary).get(_outfit, {}) as Dictionary).get("node", ""))
	var far_src: MeshInstance3D = null
	for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := str(m.name)
		if n == _variant:
			_mesh = m
		elif n == gear_name and gear_name != "":
			_gear = m
		elif n == far_name:
			far_src = m
		m.visible = false
	if _mesh == null:
		_model.free()
		_model = null
		return false
	_sk = _mesh.get_node_or_null(_mesh.skeleton) as Skeleton3D
	if _sk == null:
		return false
	_material = _make_material(entry, body_key)
	for m: MeshInstance3D in [_mesh, _gear]:
		if m != null:
			m.visible = true
			m.material_override = _material
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _gear != null:
		_gear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the far mesh: a copy under Body (the model's turn and scale), shown without a slot
	_far = MeshInstance3D.new()
	_far.name = FAR_NAME
	_far.mesh = far_src.mesh if far_src != null else null
	_far.material_override = _material
	_far.transform = _model.transform
	_far.visible = false
	body.add_child(_far)
	for c in _model.get_children():
		if c != _sk.get_parent():
			_model.remove_child(c)
			c.free()   # the other variants' skeletons and the far meshes (the copy above draws it)
	for i in _sk.get_bone_count():
		_bones[_sk.get_bone_name(i)] = i
	var l1 := _sk.get_bone_global_rest(_bones.upperarm_r).origin.distance_to(_sk.get_bone_global_rest(_bones.lowerarm_r).origin)
	var l2 := _sk.get_bone_global_rest(_bones.lowerarm_r).origin.distance_to(_sk.get_bone_global_rest(_bones.hand_r).origin)
	_fist = PersonRig.FIST_LOCAL * (l2 / HUMAN_FOREARM_M)
	_reach = (l1 + l2 + _fist.length()) * _scale
	# the clips: the gaits' strides from the manifest, a player rooted at the skeleton's parent
	var gaits: Dictionary = ((_facts.get(_creature, {}) as Dictionary).get("clips", {}) as Dictionary).get("gaits", {})
	for g: String in ["walk", "run"]:
		_stride[g] = float((gaits.get(g, {}) as Dictionary).get("stride_m", 3.0)) * _scale
	_run_from = 0.5 * (float(record.get("walk_speed_mps", 2.0)) + float(record.get("run_speed_mps", 4.0)))
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_sk.get_parent().add_child(_player)
	_player.root_node = NodePath("..")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var lib := clip_library(_creature)
	if lib != null:
		_player.add_animation_library(LIBRARY, lib)
	_sk.name = "Skeleton3D"
	_build_club(record)
	return true


## The body's material: person.gdshader on the creature's atlas, the record's palette over the kind's.
func _make_material(entry: Dictionary, body_key: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PersonModel.PERSON_SHADER)
	for key: String in ["albedo", "normal", "orm"]:
		if ResourceLoader.exists(str(entry.get(key, ""))):
			m.set_shader_parameter(StringName(key + "_tex"), load(str(entry[key])))
	if ResourceLoader.exists(str(entry.get("orm", ""))):
		m.set_shader_parameter(&"band_tex", load(str(entry.orm)))
	var pal: Dictionary = (PALETTES.get(_creature, PALETTES.ogre) as Dictionary).duplicate()
	var over: Variant = body_key.get("palette")
	if over is Dictionary:
		pal.merge(over, true)
	for band: String in ["skin", "hair", "cloth", "faction"]:
		m.set_shader_parameter(StringName(band + "_color"), Color.html(str(pal[band])))
	return m


## The creature's clips (a copy of <creature>_clips.glb's: every track retargeted to "Skeleton3D:<bone>" so the
## whelp's skeleton takes the troll's clips, the loops set), held for the process.
static func clip_library(creature: String) -> AnimationLibrary:
	if _libs.has(creature):
		return _libs[creature]
	var entry: Dictionary = creature_index().get(creature, {})
	var path := str(entry.get("clips", ""))
	if not ResourceLoader.exists(path):
		return null
	var src := load(path) as AnimationLibrary
	var lib := src.duplicate(true) as AnimationLibrary
	for an: StringName in lib.get_animation_list():
		var a := lib.get_animation(an)
		for t in a.get_track_count():
			a.track_set_path(t, NodePath("Skeleton3D:" + str(a.track_get_path(t)).get_slice(":", 1)))
		a.loop_mode = Animation.LOOP_LINEAR if str(an) in ["idle", "walk", "run", "charge_run", "idle2", "walk2", "run2"] \
			else Animation.LOOP_NONE   # A2: Stoneback's charge run; C2: the Broken Warden's two-handed stances
	_libs[creature] = lib
	return lib


static func clip_length(creature: String, clip: String) -> float:
	var lib := clip_library(creature)
	return lib.get_animation(clip).length if lib != null and lib.has_animation(clip) else 1.0


## The club: a stripped limb, thicker toward its end, with knots; the King's banded in gold (vertex colours: the
## person shader's gear mode, so it flashes and tints with the body).
func _build_club(record: Dictionary) -> void:
	var banded := _outfit == "ogre_king"
	var key := "banded" if banded else "plain"
	if not _clubs.has(key):
		_clubs[key] = club_mesh(banded)
	_club_material = PersonModel.gear_material()
	_socket = Node3D.new()
	_socket.name = SOCKET_NAME
	body.add_child(_socket)
	_club = MeshInstance3D.new()
	_club.name = "Club"
	_club.mesh = _clubs[key]
	_club.material_override = _club_material
	_club.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var length := CLUB_M_AT_OGRE * float(record.get("height_m", OGRE_H)) / OGRE_H
	_club.scale = Vector3.ONE * length
	_socket.add_child(_club)


## A club one unit long along +Y from its grip (a little behind the grip for the hand), 0.07 across at the grip and
## 0.15 at the end, gnarled; `banded`: two gold bands (the King's).
static func club_mesh(banded: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	var rings := 14
	var wood := Color(0.32, 0.22, 0.13, 0.0)
	var dark := Color(0.2, 0.14, 0.09, 0.0)
	var gold := Color(0.78, 0.6, 0.2, 0.0)
	var pts: Array = []
	for r in rings + 1:
		var y := lerpf(-0.08, 1.0, float(r) / rings)
		var base := lerpf(0.035, 0.075, smoothstep(-0.08, 1.0, y))
		if y > 0.93:
			base *= lerpf(1.0, 0.55, (y - 0.93) / 0.07)
		var row: Array = []
		for s in sides:
			var a := TAU * s / sides
			var knot := 0.012 * sin(a * 3.0 + y * 9.0) + 0.009 * sin(a * 5.0 - y * 23.0)
			var rad := base + knot * smoothstep(0.1, 0.4, y)
			var bend := Vector3(0.02 * sin(y * 3.1), 0.0, 0.015 * sin(y * 2.3 + 1.0))
			row.append(Vector3(cos(a) * rad, y, sin(a) * rad) + bend)
		pts.append(row)
	for r in rings:
		var y0 := lerpf(-0.08, 1.0, float(r) / rings)
		var c := wood.lerp(dark, 0.5 + 0.5 * sin(float(r) * 2.3)) if r % 4 == 1 else wood
		if banded and (absf(y0 - 0.55) < 0.05 or absf(y0 - 0.78) < 0.05):
			c = gold
		for s in sides:
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][(s + 1) % sides]
			var cc: Vector3 = pts[r + 1][(s + 1) % sides]
			var d: Vector3 = pts[r + 1][s]
			st.set_color(c)
			for p: Vector3 in [a, cc, b, a, d, cc]:
				st.add_vertex(p)
	# the end caps
	for cap in [0, rings]:
		var ring: Array = pts[cap]
		var centre := Vector3(0.0, (ring[0] as Vector3).y, 0.0)
		for s in sides:
			st.set_color(dark)
			var a: Vector3 = ring[s]
			var b: Vector3 = ring[(s + 1) % sides]
			if cap == 0:
				for p: Vector3 in [centre, a, b]:
					st.add_vertex(p)
			else:
				for p: Vector3 in [centre, b, a]:
					st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## The dormant level's stand-in (AI LOD tier 2): Visual/LodProxy shows the far mesh in the body's material.
func _fill_lod_proxy() -> void:
	var proxy := get_node_or_null("LodProxy") as MeshInstance3D
	if proxy == null or _far == null or _far.mesh == null:
		return
	proxy.mesh = _far.mesh
	proxy.material_override = _material
	proxy.transform = _model.transform


# --------------------------------------------------------------------------- the slots (CreatureSlots)

func slot_wanted() -> bool:
	return _mode == 1 and is_inside_tree() and actor != null and actor.visible \
		and not (actor is EnemyActor and (actor as EnemyActor).lod_tier >= 2 and not _held())


func slot_priority(cam: Vector3) -> float:
	var d := actor.global_position.distance_to(cam)
	if render_lod_m > 0.0 and d > render_lod_m and not _boss and not _held():
		return INF
	if _slot:
		d *= CreatureSlots.KEEP_SHARE
	if _boss:
		return CreatureSlots.BOSS + d
	var s := rig_state()
	if _death_len < 0.0:
		_death_len = clip_length(_creature, "death")
	var dead_done := _dead_t >= _death_len + 1.0
	if _held() or (not dead_done and (s.get("action") != null or bool(s.get("staggered", false)) or bool(s.get("dead", false)))):
		return CreatureSlots.ACTING + d
	return d + (1000.0 if dead_done else 0.0)


func set_slot(on: bool) -> void:
	if _slot_applied and on == _slot and _frozen == (not on and _dead_t >= 0.0):
		return
	_slot_applied = _model != null
	_slot = on
	_frozen = not on and _dead_t >= 0.0
	if _model == null:
		return
	var show_model := on or _frozen
	_model.visible = show_model
	_far.visible = not show_model
	if _socket != null:
		_socket.visible = show_model


func has_slot() -> bool:
	return _slot


func _held() -> bool:
	return actor != null and actor.has_method("is_held") and bool(actor.call("is_held"))


# --------------------------------------------------------------------------- the frame

## The box rig's pivots are left alone while the creature shows (ActorRig._box_posed): the brain's arm poses and
## twist stay values.
func _box_posed() -> bool:
	return _mode != 1


func _process(delta: float) -> void:
	super._process(delta)
	if actor == null or not actor.has_method("get_rig_state"):
		return
	if _mode < 0:
		_decide()
	if _mode != 1:
		return
	_time += delta
	var s := rig_state()
	if bool(s.get("dead", false)):
		_dead_t = maxf(_dead_t, 0.0) + delta
	elif _dead_t >= 0.0:
		_dead_t = -1.0
	CreatureSlots.allocate(self)
	if not _slot or not is_visible_in_tree() or not body.visible:
		CreatureSlots.totals.far_frames = int(CreatureSlots.totals.far_frames) + (0 if _slot else 1)
		_half_dt = 0.0
		return
	# P64b: out of view, or far and idle, the body poses every other frame (CreatureSlots.half_rate)
	var acting := s.get("action") != null or bool(s.get("staggered", false)) or bool(s.get("dead", false)) or _held()
	if not _half_skip and CreatureSlots.half_rate(actor.global_position + Vector3.UP * 0.5 * _height, 0.75 * _height,
			render_lod_m, acting):
		_half_skip = true
		_half_dt += delta
		CreatureSlots.totals.half_rate_skips = int(CreatureSlots.totals.half_rate_skips) + 1
		return
	_half_skip = false
	_skinned_frame(s, delta + _half_dt)
	_half_dt = 0.0


## The brain's body lean, without its fall when skinned: the death clip falls the body.
func _update_body(s: Dictionary, delta: float) -> void:
	if _mode == 1 and bool(s.get("dead", false)):
		body.rotation = body.rotation.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
		body.position = body.position.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
		_fall = move_toward(_fall, 1.0, delta * 1.6)
		return
	super._update_body(s, delta)


func _skinned_frame(s: Dictionary, delta: float) -> void:
	skinned_frames += 1
	CreatureSlots.totals.skinned_frames = int(CreatureSlots.totals.skinned_frames) + 1
	var acting := _play(s, delta)
	_pose_arms(s, delta, acting)
	_lay_dead_arm(s)
	_place_club()


## The clip and its time (see the class notes); returns whether the arms follow the brain's poses.
func _play(s: Dictionary, delta: float) -> bool:
	if _player == null or not _player.has_animation_library(LIBRARY):
		return false
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var speed := float(s.get("speed", 0.0))
	var held := _held()
	var dead := bool(s.get("dead", false)) and not held
	var clip := "idle"
	var t := -1.0
	var arms := false
	var moving := speed > 0.3 and not dead and not held
	if moving:
		_gait += speed * delta
	if dead:
		clip = "death"
		t = minf(maxf(_dead_t, 0.0), clip_length(_creature, "death"))
	elif held:
		clip = "brace"
		t = 0.0
		arms = true
	elif action != null and _is_slam(action):
		clip = "slam"
		t = _phase_time(phase, f, [0.0, SLAM_TOP_S, SLAM_HIT_S, clip_length(_creature, "slam")])
	elif action != null and (_is_roar(action) or (action.hit_shape == "body_sweep" and phase == ActionDef.Phase.WINDUP)):
		clip = "roar"   # (the charge's windup: a roar before the run)
		t = _phase_time(phase, f, [0.0, ROAR_TOP_S, ROAR_HOLD_S, clip_length(_creature, "roar")])
	elif moving and (action == null or action.hit_shape == "body_sweep"):
		clip = "run" if speed >= _run_from or (action != null and action.hit_shape == "body_sweep") else "walk"
		t = fposmod(_gait / maxf(float(_stride[clip]), 0.1), 1.0) * clip_length(_creature, clip)
	elif action != null and action.is_attack() and action.hit_shape != "body_sweep":
		clip = "brace"
		t = 0.0
		arms = true
	elif int(s.get("state", 0)) == CombatController.State.BLOCKING or bool(s.get("guarding", false)):
		clip = "brace"
		t = 0.0
		arms = true
	if clip != _clip:
		var first := _clip == ""
		_clip = clip
		_player.play(StringName(String(LIBRARY) + "/" + clip), 0.0 if first else FADE_S)
		_clip_t = 0.0
	if t < 0.0:
		_clip_t += delta
		t = _clip_t
	var length := clip_length(_creature, clip)
	var loops := clip in ["idle", "walk", "run"]
	var before := fposmod(t - delta, length) if loops else maxf(t - delta, 0.0)
	_player.seek(before, false)
	_player.advance(delta if loops or t >= delta else t)
	return arms


## A clip's time from an action's phase: keys [start, end of the windup, end of the active phase, end]; the windup
## eased out (the box rig's ease), the active phase and the recovery linear.
static func _phase_time(phase: int, f: float, keys: Array) -> float:
	match phase:
		ActionDef.Phase.WINDUP:
			var e := 1.0 - (1.0 - f) * (1.0 - f)
			return lerpf(float(keys[0]), float(keys[1]), e)
		ActionDef.Phase.ACTIVE:
			return lerpf(float(keys[1]), float(keys[2]), f)
		ActionDef.Phase.RECOVERY:
			return lerpf(float(keys[2]), float(keys[3]), f)
	return float(keys[0])


## The slam's clip: a ground pulse (the box rig's both-arms slam: a cylinder pulse without morale damage).
static func _is_slam(a: ActionDef) -> bool:
	return a.hit_shape == "cylinder_pulse" and float(a.param("morale_damage", 0.0)) <= 0.0


## The roar's clip: a phase's roar (hit shape none) or a pulse that breaks morale.
static func _is_roar(a: ActionDef) -> bool:
	return a.hit_shape == "none" or (a.hit_shape == "cylinder_pulse" and float(a.param("morale_damage", 0.0)) > 0.0)


## The arms on the brain's poses (see the class notes), weighted in and out at ARM_RATE; the torso's twist.
func _pose_arms(s: Dictionary, delta: float, acting: bool) -> void:
	_w_arm = move_toward(_w_arm, 1.0 if acting else 0.0, delta * ARM_RATE)
	_w_off = move_toward(_w_off, 1.0 if acting else 0.0, delta * ARM_RATE)
	if _w_arm <= 0.0 and _w_off <= 0.0:
		return
	var m := body.global_transform.affine_inverse() * _sk.global_transform
	var mi := m.affine_inverse()
	var to_body := (transform * body.transform).affine_inverse()
	var arm := arm_pose()
	var off := off_pose()
	if _held():
		var shake := Vector2(sin(_time * 13.0), cos(_time * 11.0)) * 12.0
		arm = HELD_POSE + shake
		off = Vector2(-HELD_POSE.x, HELD_POSE.y) - shake
	var action: ActionDef = s.get("action")
	if action != null and action.hit_shape == "sector_pulse" and not _held():
		_sweep_arms(s, action, m, mi)
		return
	var twist := torso_twist() * _w_arm
	if absf(twist) > 1e-5:
		var q := Basis(Vector3.UP, twist / 3.0)
		for b: String in ["spine_01", "spine_02", "spine_03"]:
			var i: int = _bones[b]
			var gp := _sk.get_bone_global_pose(i)
			PersonRig._set_global_rotation(_sk, i, q * gp.basis)
	for side: String in ["r", "l"]:
		var w := _w_arm if side == "r" else _w_off
		if w <= 0.0:
			continue
		var pose := arm if side == "r" else off
		var dir := (to_body.basis * AttackGeometry.local_direction(pose.x, clampf(pose.y, -80.0, 85.0))).normalized()
		var sh := m * _sk.get_bone_global_pose(_bones["upperarm_" + side]).origin
		var fist := _fist if side == "r" else _fist * Vector3(-1.0, 1.0, 1.0)
		PersonRig.solve_arm(_sk, _bones, side, m, mi, sh + dir * 0.9 * _reach, dir, w, _scale, fist)


## P64b: the sweep, two-handed (the sweeps, the combos, the frenzy, the whelp's swipe: every sector pulse). The box
## rig's sweep - its weapon arm thrown straight out behind, its off arm raised in a guard - put onto a real arm read
## as a T-pose with one arm over the head. Here both fists hold the club's handle, on the brain's clock (the action's
## phase and fraction, the box rig's easing): the windup draws it back high over the right shoulder (SWEEP_KEYS'
## "wound"), the torso turned away from the swing; the active phase swings it across at the chest, the arms reaching
## out in front at mid swing, the torso turning through; the recovery lets it come down and round to the left as the
## off hand lets go. A combo's or a frenzy's second blow (an id ending "_2") is the backhand: the same, mirrored.
## Each key: [the right fist's direction from its shoulder (yaw, pitch degrees: AttackGeometry's), its share of the
## arm's reach, the club's direction (yaw, pitch), the torso's twist (degrees, + toward the right)].
const SWEEP_KEYS := {
	"ready": [Vector2(25.0, -45.0), 0.8, Vector2(40.0, 10.0), 0.0],
	"wound": [Vector2(68.0, 30.0), 0.5, Vector2(165.0, 30.0), 32.0],
	"mid": [Vector2(-5.0, 8.0), 0.92, Vector2(-25.0, 2.0), 0.0],
	"swept": [Vector2(-70.0, 4.0), 0.78, Vector2(-135.0, 5.0), -34.0],
	"down": [Vector2(-25.0, -55.0), 0.85, Vector2(-70.0, -35.0), 0.0],
}
## The off fist on the handle: this share of the club's length above the right fist.
const SWEEP_GRIP_GAP := 0.11


static func _sweep_key(k: String, mirror: bool) -> Array:
	var a: Array = (SWEEP_KEYS[k] as Array).duplicate()
	if mirror:
		a[0] = Vector2(-(a[0] as Vector2).x, (a[0] as Vector2).y)
		a[2] = Vector2(-(a[2] as Vector2).x, (a[2] as Vector2).y)
		a[3] = -float(a[3])
	return a


static func _sweep_mix(a: Array, b: Array, t: float) -> Array:
	return [(a[0] as Vector2).lerp(b[0], t), lerpf(a[1], b[1], t), (a[2] as Vector2).lerp(b[2], t), lerpf(a[3], b[3], t)]


## The sweep's key now ([fist direction, reach share, club direction, twist]) and the off hand's weight on the club.
static func sweep_pose(phase: int, f: float, backhand: bool) -> Array:
	var t := clampf(f, 0.0, 1.0)
	var k: Array
	var two := 1.0
	match phase:
		ActionDef.Phase.WINDUP:
			k = _sweep_mix(_sweep_key("ready", backhand), _sweep_key("wound", backhand), 1.0 - (1.0 - t) * (1.0 - t))
			two = smoothstep(0.0, 0.35, t)
		ActionDef.Phase.ACTIVE:
			# through the middle on a curve: out in front at mid swing
			var u := smoothstep(0.0, 1.0, t)
			if u < 0.5:
				k = _sweep_mix(_sweep_key("wound", backhand), _sweep_key("mid", backhand), u * 2.0)
			else:
				k = _sweep_mix(_sweep_key("mid", backhand), _sweep_key("swept", backhand), u * 2.0 - 1.0)
		ActionDef.Phase.RECOVERY:
			k = _sweep_mix(_sweep_key("swept", backhand), _sweep_key("down", backhand), smoothstep(0.0, 1.0, t))
			two = 1.0 - smoothstep(0.1, 0.6, t)
		_:
			k = _sweep_key("ready", backhand)
			two = 0.0
	return [k, two]


func _sweep_arms(s: Dictionary, action: ActionDef, m: Transform3D, mi: Transform3D) -> void:
	var to_body := (transform * body.transform).affine_inverse()
	var backhand := action.id.ends_with("_2")
	var sp := sweep_pose(int(s.get("phase", ActionDef.Phase.NONE)), float(s.get("phase_fraction", 0.0)), backhand)
	var k: Array = sp[0]
	var fist_dir := (to_body.basis * AttackGeometry.local_direction((k[0] as Vector2).x, (k[0] as Vector2).y)).normalized()
	var club_dir := (to_body.basis * AttackGeometry.local_direction((k[2] as Vector2).x, (k[2] as Vector2).y)).normalized()
	var twist := deg_to_rad(float(k[3])) * _w_arm
	if absf(twist) > 1e-5:
		var q := Basis(Vector3.UP, twist / 3.0)
		for b: String in ["spine_01", "spine_02", "spine_03"]:
			var i: int = _bones[b]
			PersonRig._set_global_rotation(_sk, i, q * _sk.get_bone_global_pose(i).basis)
	var sh := m * _sk.get_bone_global_pose(_bones.upperarm_r).origin
	var target := sh + fist_dir * float(k[1]) * _reach
	PersonRig.solve_arm(_sk, _bones, "r", m, mi, target, club_dir, _w_arm, _scale, _fist)
	# the off fist on the handle above the right fist, along the club's line as the right hand holds it
	var hand := _sk.get_bone_global_pose(_bones.hand_r)
	var fist_r := m * (hand * _fist)
	var axis := (m.basis * (hand.basis * CLUB_AXIS.normalized())).normalized()
	var length := _club.scale.y if _club != null else CLUB_M_AT_OGRE * _scale
	var w_off := _w_off * float(sp[1])
	if w_off > 0.0:
		PersonRig.solve_arm(_sk, _bones, "l", m, mi, fist_r + axis * SWEEP_GRIP_GAP * length, axis, w_off, _scale,
			_fist * Vector3(-1.0, 1.0, 1.0))


## P64c: the death clip leaves the club arm raised off the ground (the ogre's corpse held its club up): over the
## clip's second half the right arm is laid out on the ground beside the body and the club lies flat in the fist.
func _dead_weight() -> float:
	if _dead_t < 0.0 or _held():
		return 0.0
	if _death_len < 0.0:
		_death_len = clip_length(_creature, "death")
	return smoothstep(0.45, 1.0, _dead_t / maxf(_death_len, 0.1))


func _lay_dead_arm(s: Dictionary) -> void:
	var w := _dead_weight()
	if w <= 0.0 or not bool(s.get("dead", false)):
		return
	var m := body.global_transform.affine_inverse() * _sk.global_transform
	var mi := m.affine_inverse()
	var sh := m * _sk.get_bone_global_pose(_bones.upperarm_r).origin
	var hip := m * _sk.get_bone_global_pose(_bones.pelvis).origin
	var out := Vector3(sh.x - hip.x, 0.0, sh.z - hip.z)
	var side := (m.basis * Vector3.LEFT).normalized()   # (the creature's right: its model is turned 180 degrees)
	side = Vector3(side.x, 0.0, side.z).normalized()
	out = (out.normalized() * 0.5 + side * 0.5).normalized() if out.length_squared() > 1e-6 else side
	var target := sh + out * 0.8 * _reach
	target.y = minf(target.y, DEAD_ARM_GROUND * _height)
	PersonRig.solve_arm(_sk, _bones, "r", m, mi, target, out, w, _scale, _fist)


## The club's line on the ground, by the death's weight (see _lay_dead_arm).
const DEAD_ARM_GROUND := 0.06


## The club on the right fist, along the handle's line through the fist (as a person carries a weapon).
func _place_club() -> void:
	if _socket == null:
		return
	var m := body.global_transform.affine_inverse() * _sk.global_transform
	var hand := _sk.get_bone_global_pose(_bones.hand_r)
	var fist := m * (hand * _fist)
	var y := (m.basis * (hand.basis * CLUB_AXIS.normalized())).normalized()
	var dw := _dead_weight()
	if dw > 0.0 and absf(y.y) < 0.999:
		y = y.slerp(Vector3(y.x, 0.0, y.z).normalized(), dw).normalized()   # P64c: it lies flat
	var z := (m.basis * hand.basis.y).normalized()
	z = z - y * y.dot(z)
	if z.length_squared() < 1e-6:
		z = Vector3.BACK - y * y.dot(Vector3.BACK)
	z = z.normalized()
	_socket.transform = Transform3D(Basis(y.cross(z), y, z), fist)


# --------------------------------------------------------------------------- paint and reads

func _update_flash(delta: float) -> void:
	var active := _flash > 0.0 or _flash_applied > 0.0 or _tint_dirty
	super._update_flash(delta)
	if active and _mode == 1:
		RigPaint.paint_shaders([_material, _club_material].filter(func(x: Variant) -> bool: return x != null), _tint,
			_flash_applied, _flash_color)


func model() -> Node3D:
	return _model


func skeleton() -> Skeleton3D:
	return _sk


func body_mesh() -> MeshInstance3D:
	return _mesh


func gear_mesh() -> MeshInstance3D:
	return _gear


func far_mesh() -> MeshInstance3D:
	return _far


func club() -> MeshInstance3D:
	return _club


func material() -> ShaderMaterial:
	return _material


func current_clip() -> String:
	return _clip


func arm_weights() -> Dictionary:
	return {"arm": _w_arm, "off": _w_off}


func model_scale() -> float:
	return _scale


## The creature, the variant and the outfit shown ({} until skinned).
func creature_spec() -> Dictionary:
	return {} if _mode != 1 else {"creature": _creature, "variant": _variant, "outfit": _outfit, "scale": _scale,
		"boss": _boss}
