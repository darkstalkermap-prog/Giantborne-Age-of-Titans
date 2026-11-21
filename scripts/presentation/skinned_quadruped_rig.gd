class_name SkinnedQuadrupedRig
extends QuadrupedRig
## The cavalry's horse skinned in play, with its rider (P62; plan M11 §2.10, §3.15 design 2). The brain stays: this
## is a QuadrupedRig, whose _process poses the box rig's pivots (Body, Body/Head, Body/Tail, the four legs) from the
## actor's state on the frame clock as before, counts the footfalls and keeps the hit flash and the status tint. On
## top, where the people are drawn (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never with
## --no-skin) and the record's `body.rig` is not "box", the box rig's meshes hide and the realistic horse shows:
##
##   Visual (SkinnedQuadrupedRig)
##   └ Body                         leans, lunges, staggers and rolls as the brain says (QuadrupedRig)
##     ├ (the box rig's pivots and merged meshes, hidden)
##     └ Horse                      the creature's glTF (assets/creatures: the manifest's scene), turned 180 degrees
##       └ Skeleton3D               25 bones, driven here (no clip): the legs, the neck, the jaw, the tail
##         ├ horse_tacked           one surface (body, mane, tail, saddle, straps, irons, housing): person.gdshader
##         │                        with the horse's atlas, the mane's and tail's strands cut by alpha scissor
##         └ Rider                  a pooled PersonModel (the record's body role: the rider's) in the `seated` clip,
##           │                      its origin on the saddle's seat (the manifest's saddle_seat on spine_01)
##           └ LanceSocket          the lance (gear.glb's spear fitted to 4.2 m) in the right fist
##
## The gait (no clip: the horse's files carry only its extremes) is planned in the world: each leg is in stance or in
## swing; a planted hoof stays where it landed (no foot slides, whatever the speed or the turn), a swing carries it
## along an arc to where its stance will be centred under its hip half a stance later. The legs' timing comes from
## the speed: the walk (four beats, the lateral sequence), the trot (the diagonal pairs) and the gallop (the
## transverse gallop, right lead), their phase offsets and stance shares blended by speed, so a gait never pops into
## the next; a hoof the body has carried past its reach lifts early. The legs are then solved in the skeleton's
## space: the hoof's pastern as at rest, the cannon plumb (tilted toward the hip or shoulder only as far as the leg
## must reach), the upper and lower bones by a two-bone solve bending as at rest (the elbow back, the stifle
## forward); in swing the knee and the hock fold. The body bobs, pitches and leans into a turn from the same clock;
## the neck nods, the head follows the brain's head pivot (raised in a windup), the tail sways and lifts at speed.
## Standing, a hoof left off its place steps back to it, one leg at a time.
##
## The rider: the seated clip, the trunk leaning forward with the gait, the right arm by PersonRig.solve_arm onto the
## lance's grip: carried upright beside the right knee at rest, couched level at the right hip for the charge (lowered
## through the charge's windup, its telegraph), thrust forward in the lance attack; the left hand stays on the reins.
## Dead, held or thrown, the legs hang and the rider sits on. Draw calls: the horse, the rider and the lance (3); two
## shadow draws a cascade (the horse and the rider).
##
## A horse and its rider are one of plan §2.10's "others", not of the people's cap: at most MAX_SKINNED_OTHERS
## animate every frame (the nearest the camera), the rest every THROTTLE_FRAMES frames. AI LOD tier 2
## (dormant): Visual/LodProxy shows the horse's mesh at rest with the rider's seated pose mesh. Headless, with
## --no-skin, or with `body.rig` "box", the box rig draws as before (the beasts' gate's fallback, plan §3.18).
##
## Presentation only: this rig writes under its own Visual node and reads the actor; nothing in the simulation reads
## it (plan M10 §2.7).

const HORSE_NAME := "Horse"
const RIDER_NAME := "Rider"
const SOCKET_NAME := "LanceSocket"
const CREATURES_MANIFEST := "res://assets/creatures/manifest.json"
## At most this many horses (plan §2.10's "others") animate every frame; the rest every THROTTLE_FRAMES frames.
const MAX_SKINNED_OTHERS := 8
const THROTTLE_FRAMES := 3
const GROUP := "skinned_quadruped_rigs"
const LEGS := ["fore_l", "fore_r", "hind_l", "hind_r"]
## The gaits' phase offsets of each leg (fractions of the cycle; LEGS' order): the walk's lateral sequence (left
## hind, left fore, right hind, right fore), the trot's diagonal pairs, the transverse gallop on the right lead (left
## hind, right hind, left fore, right fore, then the suspension).
const WALK_OFF := [0.25, 0.75, 0.0, 0.5]
const TROT_OFF := [0.5, 1.0, 0.5, 1.0]
const GALLOP_OFF := [0.4, 0.52, 0.0, 0.1]
## Each gait's share of the cycle a hoof stands (the duty factor).
const WALK_DUTY := 0.6
const TROT_DUTY := 0.4
const GALLOP_DUTY := 0.26
const FAST_GALLOP_DUTY := 0.15
## The gaits blend over these speeds (m/s): the walk into the trot, the trot into the gallop; the gallop's duty
## falls to FAST_GALLOP_DUTY by FAST_MPS.
const TROT_FROM := Vector2(1.8, 2.6)
const GALLOP_FROM := Vector2(5.5, 8.0)
const FAST_MPS := 14.0
## Moving below this (m/s) the horse stands: no new stride starts.
const STAND_MPS := 0.25
## A swing's hoof lift (m) at the walk, the trot and the gallop (the hind feet lift HIND_LIFT of it).
const LIFT := Vector3(0.11, 0.2, 0.28)
const HIND_LIFT := 0.8
## The knee's and the hock's fold in a swing (degrees at mid swing: the cannon's tilt, the pastern's further fold).
const FORE_FOLD := Vector2(75.0, 40.0)
const HIND_FOLD := Vector2(-22.0, 35.0)
## A planted hoof farther than this from its place (m, times the gait's reach share) lifts at once.
const REACH_FORE_M := 0.62
const REACH_HIND_M := 0.72
## A standing hoof farther than BREAKOVER_FROM_M behind its hip or shoulder joint breaks over (the heel lifts over
## the toe), by up to BREAKOVER_DEG BREAKOVER_M further behind.
const BREAKOVER_FROM_M := 0.22
const BREAKOVER_M := 0.25
const BREAKOVER_DEG := 40.0
## The shoulder's slide with the foreleg (the scapula's swing, which the 25 bones do not carry): this share of the
## hoof's distance before or behind the shoulder joint, at most SCAPULA_M.
const SCAPULA_SHARE := 0.3
const SCAPULA_M := 0.12
## A moving fore hoof's stance is centred this far before its rest place (m: under the shoulder joint).
const FORE_AHEAD_M := 0.1
## Standing: a hoof this far off its place (m) steps back to it, in STEP_S seconds.
const SETTLE_M := 0.1
const STEP_S := 0.32
## The body's bob (m) and pitch (degrees) at the walk, the trot and the gallop.
const BOB := Vector3(0.012, 0.025, 0.03)
const PITCH_DEG := Vector3(0.6, 0.8, 2.5)
## The lean into a turn: the centripetal share (atan(v w / g)), at most LEAN_MAX_DEG.
const LEAN_MAX_DEG := 14.0
## The neck's nod (degrees) at the walk, the trot and the gallop; the jaw's opening at the gallop.
const NOD_DEG := Vector3(4.0, 1.5, 6.0)
const JAW_GALLOP_DEG := 6.0
## The tail's lift (degrees) at the gallop, its sway's share of the brain's tail pivot.
const TAIL_LIFT_DEG := 28.0
## A move farther than this in one frame is a teleport: the hooves are put back on their places.
const TELEPORT_M := 3.0
## The rider's lean forward (degrees over the three spine bones) at the gallop and in the charge.
const RIDER_LEAN_DEG := 14.0
## The lance (gear.glb's spear: its grip at the origin, its length along +Y) fitted as the pikes are (PersonRig's
## GEAR_FIT: 4.2 m, 3.5 m before the hand).
const LANCE_FIT := {"scale": 1.6, "shift": 1.22}
## The lance's grip in the rider's space (Visual's axes: -Z the front, +X the right; metres from the saddle's seat)
## and its direction: carried upright by the right knee, couched at the right hip, thrust (the lance attack's
## active phase).
const CARRY_GRIP := Vector3(0.24, 0.22, -0.16)
const CARRY_DIR := Vector3(0.05, 0.98, -0.2)
const COUCH_GRIP := Vector3(0.22, 0.2, -0.22)
const COUCH_DIR := Vector3(-0.1, -0.05, -1.0)
const THRUST_GRIP := Vector3(0.2, 0.32, -0.58)
const THRUST_DIR := Vector3(-0.06, -0.18, -1.0)
const LANCE_RATE := 5.0
## The left fist on the reins (the rider's space), before the pommel over the withers, the hand's line forward.
const REINS_GRIP := Vector3(-0.07, 0.2, -0.36)
const REINS_HAND := Vector3(0.25, -0.35, -1.0)
## The horse's coats (the palette's skin band: the coat; hair: the mane, the tail and the points), one by a hash of
## the entity id: bay, dark bay, chestnut, grey, black, dun.
const COATS := [["#6e4126", "#17120e"], ["#432a19", "#100c0a"], ["#8c4b25", "#6a3418"], ["#9b968c", "#5e5a55"],
	["#28231f", "#121010"], ["#a3875a", "#2a2119"]]

static var _index: Dictionary = {}
static var _rigs: Array = []
static var _alloc_frame := -1

var skinned := false
## The record's `body` decision: -1 undecided (the actor reads its record after this rig is ready), 0 box, 1 skinned.
var _mode := -1
var _pending_lod := 0.0
var _horse: Node3D = null
var _sk: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _material: ShaderMaterial = null
var _rider: PersonModel = null
var _rider_look: Dictionary = {}
var _rider_bones := {}
var _rider_grip := {}
var _lance_socket: Node3D = null
var _lance: MeshInstance3D = null
var _gear_material: ShaderMaterial = null
var _bones := {}
var _rest_global := {}          # bone index -> rest global Transform3D (skeleton space)
var _legs := {}                 # leg -> {"b": [upper, lower, cannon, foot], "joints": [5 rest points], "len": [..]}
var _seat := Transform3D.IDENTITY
var _phase := 0.0
var _speed := 0.0
var _vel := Vector3.ZERO
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _yaw_rate := 0.0
var _lean := 0.0
var _w_trot := 0.0
var _w_gallop := 0.0
var _lance_w := 0.0             # 0 carried, 1 couched
var _thrust_w := 0.0
var _feet := {}                 # leg -> {"stance": bool, "pos": world sole, "from", "to", "s", "last_p", "step"}
var _throttled := false
var _skip := 0
var _accum := 0.0
## Frames posed skinned (tests, stats).
var skinned_frames := 0
## The largest slide of a planted hoof seen this life (m; tests: the gait never slides a planted hoof).
var max_planted_slide := 0.0
## The most a standing leg's solve fell short of its hoof (m; tests: a planted hoof is reached, not hovered over).
var max_reach_miss := 0.0


# --------------------------------------------------------------------------- setup

func _enter_tree() -> void:
	if not _rigs.has(self):
		_rigs.append(self)


func _exit_tree() -> void:
	_rigs.erase(self)
	_release_rider()


## The creatures' manifest index (the horse's scene, meshes, maps, bones and landmarks).
static func creature_index() -> Dictionary:
	if _index.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREATURES_MANIFEST)) \
			if FileAccess.file_exists(CREATURES_MANIFEST) else null
		if doc is Dictionary:
			_index = (doc as Dictionary).get("index", {})
	return _index


## The distance LOD: the box rig takes it as before; the skinned horse has no box proxies (it is drawn at any
## distance and animates less often far away).
func set_render_lod(lod_m: float) -> void:
	_pending_lod = maxf(0.0, lod_m)
	if _mode == 0:
		super.set_render_lod(lod_m)
	elif _mode == 1:
		render_lod_m = _pending_lod
	else:
		super.set_render_lod(lod_m)   # (undecided: as the box rig; the skinned decision removes it)


## The body the record asks for (its `body.rig`: "box" keeps the box rig) and the switch.
func _decide() -> void:
	var rec: Variant = actor.get("record") if actor != null and "record" in actor else null
	var body_key: Dictionary = (rec as Dictionary).get("body", {}) if typeof(rec) == TYPE_DICTIONARY \
		and typeof((rec as Dictionary).get("body")) == TYPE_DICTIONARY else {}
	var want := str(body_key.get("rig", "skinned")) != "box"
	if typeof(rec) == TYPE_DICTIONARY and (rec as Dictionary).is_empty():
		return   # the record is not read yet
	_mode = 1 if want and PersonRig.layers_enabled() and _build_horse(body_key) else 0
	skinned = _mode == 1
	if skinned:
		RigPaint.apply_render_lod(self, body, 0.0)
		if mid_proxy != null:
			RigPaint.remove_mid_lod(body, render_lod_m)
			mid_proxy = null
		render_lod_m = _pending_lod
		for c in body.get_children():
			if c != _horse and c is GeometryInstance3D:
				(c as GeometryInstance3D).visible = false
			elif c != _horse and c is Node3D:
				for g in (c as Node3D).find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).visible = false
		_fill_lod_proxy()


func _build_horse(body_key: Dictionary) -> bool:
	var h: Dictionary = creature_index().get("horse", {})
	if h.is_empty() or not ResourceLoader.exists(str(h.get("scene", ""))):
		return false
	_horse = (load(str(h.scene)) as PackedScene).instantiate() as Node3D
	_horse.name = HORSE_NAME
	body.add_child(_horse)
	_horse.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_sk = _horse.find_child("Skeleton3D", true, false) as Skeleton3D
	var meshes: Dictionary = h.get("meshes", {})
	for c in _sk.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = str(c.name) == str(meshes.get("tacked", "horse_tacked"))
			if (c as MeshInstance3D).visible:
				_mesh = c as MeshInstance3D
	if _mesh == null:
		return false
	_material = horse_material(h)
	var id := str(actor.get("entity_id")) if "entity_id" in actor else str(actor.name)
	var faction := str(actor.get("faction")) if "faction" in actor else ""
	var coat: Array = COATS[absi(hash(id + "#coat")) % COATS.size()]
	var person_role := str(body_key.get("role", "person_role.rider"))
	_material.set_shader_parameter(&"skin_color", Color.html(str(coat[0])))
	_material.set_shader_parameter(&"hair_color", Color.html(str(coat[1])))
	_material.set_shader_parameter(&"cloth_color", Color(0.36, 0.30, 0.22))
	_material.set_shader_parameter(&"faction_color", PersonLook.faction_color(person_role,
		faction if PersonLook.factions_of(person_role).has(faction) else PersonLook.DEFAULT_FACTION))
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in _sk.get_bone_count():
		_bones[_sk.get_bone_name(i)] = i
		_rest_global[i] = _sk.get_bone_global_rest(i)
	_index_legs(h)
	var seat: Dictionary = (h.get("landmarks", {}) as Dictionary).get("saddle_seat", {})
	var sp: Array = seat.get("position", [0.0, 1.608, 0.16])
	_seat = Transform3D(Basis(), Vector3(float(sp[0]), float(sp[1]), float(sp[2])))
	_rider_look = PersonLook.spec(body_key, id, faction, PersonModel.HEIGHT_M, {"person_role": "person_role.rider",
		"gear": ["spear"]})
	_reset_feet()
	return true


## The horse's material: person.gdshader on the horse's atlas, the strands cut (alpha scissor).
static func horse_material(h: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PersonModel.PERSON_SHADER)
	for key: String in ["albedo", "normal", "orm"]:
		if ResourceLoader.exists(str(h.get(key, ""))):
			m.set_shader_parameter(StringName(key + "_tex"), load(str(h[key])))
	m.set_shader_parameter(&"band_tex", load(str(h.get("orm", ""))) if ResourceLoader.exists(str(h.get("orm", ""))) else null)
	m.set_shader_parameter(&"strands", true)
	return m


## Each leg's bones (upper, lower, cannon, foot), its joints at rest (skeleton space: the hip or shoulder, the
## elbow or stifle, the knee or hock, the fetlock, the sole) and the segments' lengths.
func _index_legs(h: Dictionary) -> void:
	var soles: Dictionary = (h.get("landmarks", {}) as Dictionary).get("soles", {})
	for leg: String in LEGS:
		var parts := leg.split("_")
		var names := []
		for seg: String in ["upper", "lower", "cannon", "foot"]:
			names.append("%s_%s_%s" % [parts[0], seg, parts[1]])
		var b: Array = []
		var joints: Array = []
		for n: String in names:
			var i: int = _bones.get(n, -1)
			b.append(i)
			joints.append((_rest_global[i] as Transform3D).origin if i >= 0 else Vector3.ZERO)
		var so: Array = soles.get(leg, [0.0, 0.0, 0.0])
		joints.append(Vector3(float(so[0]), float(so[1]), float(so[2])))
		var lens: Array = []
		for k in 4:
			lens.append((joints[k + 1] as Vector3).distance_to(joints[k]))
		# the middle joint's bend at rest: its offset from the line hip/shoulder -> knee/hock
		var a: Vector3 = joints[0]
		var c: Vector3 = joints[2]
		var mid: Vector3 = joints[1]
		var d := (c - a).normalized()
		var pole := (mid - a) - d * (mid - a).dot(d)
		if pole.length_squared() < 1e-6:
			pole = Vector3(0.0, 0.0, -1.0 if parts[0] == "fore" else 1.0)
		_legs[leg] = {"b": b, "joints": joints, "len": lens, "pole": pole.normalized(), "fore": parts[0] == "fore"}


## The dormant level's stand-in: Visual/LodProxy shows the horse's mesh at rest (unskinned: its bind pose) and the
## rider's seated pose mesh, in the same materials.
func _fill_lod_proxy() -> void:
	var proxy := get_node_or_null("LodProxy") as MeshInstance3D
	if proxy == null or _mesh == null:
		return
	proxy.mesh = _mesh.mesh
	proxy.material_override = _material
	proxy.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var r := PersonModel.role_data(str(_rider_look.get("role", "rider")))
	var pose: Mesh = (r.get("poses", {}) as Dictionary).get("hold") if not r.is_empty() else null
	if pose != null and proxy.get_node_or_null(RIDER_NAME) == null:
		var rm := MeshInstance3D.new()
		rm.name = RIDER_NAME
		rm.mesh = pose
		var mat := PersonModel.skinned_material(str(_rider_look.get("role", "rider")))
		PersonLook.apply(mat, _rider_look)
		rm.material_override = mat
		rm.transform = _seat
		proxy.add_child(rm)


# --------------------------------------------------------------------------- the rider

func _ensure_rider() -> bool:
	if _rider != null:
		return true
	_rider = PersonModel.acquire(str(_rider_look.get("role", "rider")), str(_rider_look.get("variant", "")))
	if _rider == null:
		return false
	_rider.name = RIDER_NAME
	_sk.add_child(_rider)
	_rider.transform = _seat
	_rider.mesh_instance().cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	PersonLook.apply(_rider.material, _rider_look)
	PersonRig.variants_drawn[str(_rider_look.get("variant", ""))] = true
	var rsk := _rider.skeleton()
	_rider_bones.clear()
	for i in rsk.get_bone_count():
		_rider_bones[rsk.get_bone_name(i)] = i
	_rider_grip = PersonRig.grips_of(_rider.role, _rider.variant)
	var ap := _rider.player()
	if ap != null:
		ap.play(StringName(String(PersonModel.LIBRARY) + "/seated"), 0.0)
	if _gear_material == null:
		_gear_material = PersonModel.gear_material()
	PersonLook.apply(_gear_material, _rider_look)
	_lance_socket = Node3D.new()
	_lance_socket.name = SOCKET_NAME
	_rider.add_child(_lance_socket)
	var mesh := PersonModel.gear_mesh("spear") if (_rider_look.get("gear", []) as Array).has("spear") else null
	if mesh != null:
		_lance = MeshInstance3D.new()
		_lance.name = "Gear_lance"
		_lance.mesh = mesh
		_lance.material_override = _gear_material
		_lance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lance.transform = Transform3D(Basis.from_scale(Vector3(1.0, float(LANCE_FIT.scale), 1.0)),
			Vector3(0.0, float(LANCE_FIT.shift), 0.0))
		_lance_socket.add_child(_lance)
	_tint_dirty = true
	return true


func _release_rider() -> void:
	if _rider != null:
		if _lance_socket != null and is_instance_valid(_lance_socket):
			_lance_socket.free()
		_lance_socket = null
		_lance = null
		PersonModel.release(_rider)
		_rider = null


# --------------------------------------------------------------------------- the frame

func _process(delta: float) -> void:
	super._process(delta)
	if actor == null or not actor.has_method("get_rig_state"):
		return
	if _mode < 0:
		_decide()
	if _mode != 1:
		return
	_allocate(self)
	if not is_visible_in_tree() or not body.visible:
		return
	_accum += delta
	if _throttled:
		_skip = (_skip + 1) % THROTTLE_FRAMES
		if _skip != 0:
			return
	var dt := _accum
	_accum = 0.0
	_skinned_frame(dt)


## Which horses animate every frame: the MAX_SKINNED_OTHERS nearest the camera (once a frame for all).
static func _allocate(any: Node) -> void:
	var frame := Engine.get_process_frames()
	if _alloc_frame == frame:
		return
	_alloc_frame = frame
	var cam := any.get_viewport().get_camera_3d() if any.is_inside_tree() and any.get_viewport() != null else null
	var list: Array = []
	for r: Variant in _rigs:
		if is_instance_valid(r) and (r as SkinnedQuadrupedRig).skinned:
			var rig := r as SkinnedQuadrupedRig
			var d := rig.global_position.distance_squared_to(cam.global_position) if cam != null else 0.0
			list.append([d, rig])
	list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in list.size():
		(list[i][1] as SkinnedQuadrupedRig)._throttled = i >= MAX_SKINNED_OTHERS


func _skinned_frame(delta: float) -> void:
	if _sk == null or not _ensure_rider():
		return
	skinned_frames += 1
	var s: Dictionary = actor.get_rig_state()
	var dead := bool(s.get("dead", false))
	var held := actor.has_method("is_held") and bool(actor.call("is_held"))
	_track_motion(delta)
	var free := not dead and not held
	_update_gait(delta, free)
	# the body's bob, pitch and lean on the horse node (under Body: the brain's lean, lunge, stagger and fall)
	var g := _gait_vec()
	var bob := 0.0
	var pitch := 0.0
	if free and _speed > STAND_MPS:
		var amp := g.dot(BOB) * clampf(_speed / 2.0, 0.3, 1.0)
		var duty := _duty()
		var twice := 1.0 - _w_gallop
		bob = -amp * cos(TAU * (2.0 * twice + (1.0 - twice)) * (_phase - duty * 0.5))
		pitch = deg_to_rad(g.dot(PITCH_DEG)) * sin(TAU * _phase)
	var lean_want := 0.0
	if free:
		lean_want = clampf(atan(_speed * _yaw_rate / 9.81), -deg_to_rad(LEAN_MAX_DEG), deg_to_rad(LEAN_MAX_DEG))
	_lean = lerpf(_lean, lean_want, 1.0 - exp(-6.0 * delta))
	# (the horse's own frame: +Z its front, so its pitch about +X is nose down for a positive angle; the lean rolls
	# about its front)
	_horse.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.BACK, -_lean) * Basis(Vector3.RIGHT, pitch),
		Vector3(0.0, bob, 0.0))
	_reset_pose()
	if free:
		_solve_legs()
	_pose_head_tail(s, delta, free)
	_pose_rider(s, delta, dead)


## The actor's motion this frame (position delta, smoothed), its yaw rate; a teleport puts the hooves back.
func _track_motion(delta: float) -> void:
	var pos := actor.global_position
	var yaw := actor.global_rotation.y
	if _last_pos == Vector3.INF or pos.distance_to(_last_pos) > TELEPORT_M or delta <= 0.0:
		_last_pos = pos
		_last_yaw = yaw
		_vel = Vector3.ZERO
		_reset_feet()
		return
	var v := (pos - _last_pos) / delta
	v.y = 0.0
	_vel = _vel.lerp(v, 1.0 - exp(-12.0 * delta))
	_speed = _vel.length()
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 1.0 - exp(-8.0 * delta))
	_last_pos = pos
	_last_yaw = yaw


## The gait weights: (walk, trot, gallop) as a Vector3 of shares summing to 1.
func _gait_vec() -> Vector3:
	var walk := (1.0 - _w_trot) * (1.0 - _w_gallop)
	var trot := _w_trot * (1.0 - _w_gallop)
	return Vector3(walk, trot, _w_gallop)


func _duty() -> float:
	var fast := clampf((_speed - GALLOP_FROM.y) / (FAST_MPS - GALLOP_FROM.y), 0.0, 1.0)
	var g := _gait_vec()
	return g.x * WALK_DUTY + g.y * TROT_DUTY + g.z * lerpf(GALLOP_DUTY, FAST_GALLOP_DUTY, fast)


func _offset(i: int) -> float:
	var g := _gait_vec()
	return g.x * float(WALK_OFF[i]) + g.y * float(TROT_OFF[i]) + g.z * float(GALLOP_OFF[i])


## The stride's frequency (cycles a second) at `v` m/s: the walk's and the trot's strides lengthen with the speed
## (0.85 + 0.4 v metres), the gallop quickens from 1.85 Hz at 6 m/s by 0.07 Hz a m/s.
static func stride_hz(v: float) -> float:
	if v <= 6.0:
		return v / (0.85 + 0.4 * v)
	return 1.85 + (v - 6.0) * 0.07


## A leg's place (its sole at rest; a fore hoof's stance centred FORE_AHEAD_M further forward, under the
## shoulder, while it moves) in the world now.
func _home(leg: String) -> Vector3:
	var sole: Vector3 = (_legs[leg].joints as Array)[4]
	var ahead := FORE_AHEAD_M * clampf(_speed / 2.0, 0.0, 1.0) if bool(_legs[leg].fore) else 0.0
	return actor.global_transform * Vector3(-sole.x, 0.0, -sole.z - ahead)


func _reset_feet() -> void:
	if _legs.is_empty() or actor == null:
		return
	for leg: String in LEGS:
		var p := _home(leg)
		_feet[leg] = {"stance": true, "pos": p, "from": p, "to": p, "s": 0.0, "last_p": -1.0, "step": false, "anchor": p,
			"lift_p": -1.0}


## The legs' timing in the world (see the class notes).
func _update_gait(delta: float, free: bool) -> void:
	_w_trot = lerpf(_w_trot, smoothstep(TROT_FROM.x, TROT_FROM.y, _speed), 1.0 - exp(-4.0 * delta))
	_w_gallop = lerpf(_w_gallop, smoothstep(GALLOP_FROM.x, GALLOP_FROM.y, _speed), 1.0 - exp(-4.0 * delta))
	if not free:
		_reset_feet()
		return
	var moving := _speed > STAND_MPS
	var hz := maxf(stride_hz(_speed), 0.6)
	if moving:
		_phase = fposmod(_phase + hz * delta, 1.0)
	var duty := _duty()
	var stance_t := duty / hz
	var reach_share := 1.0 + _w_gallop * 0.1
	var any_stepping := false
	for leg: String in LEGS:
		if bool((_feet[leg] as Dictionary).step) or not bool((_feet[leg] as Dictionary).stance):
			any_stepping = true
	for i in LEGS.size():
		var leg: String = LEGS[i]
		var f: Dictionary = _feet[leg]
		var p := fposmod(_phase + _offset(i), 1.0)
		var wrapped := float(f.last_p) >= 0.0 and p < float(f.last_p) - 0.5
		var home := _home(leg)
		var reach := (REACH_FORE_M if bool(_legs[leg].fore) else REACH_HIND_M) * reach_share
		if bool(f.stance):
			var lift := false
			if moving and float(f.last_p) >= 0.0 and float(f.last_p) < duty and p >= duty:
				lift = true   # the stance ended on the clock
			if moving and Vector2(f.pos.x - home.x, f.pos.z - home.z).length() > reach:
				lift = true   # carried past its reach
			if not moving and not any_stepping and Vector2(f.pos.x - home.x, f.pos.z - home.z).length() > SETTLE_M:
				lift = true   # standing: back to its place
				f.step = true
				any_stepping = true
			if lift:
				f.stance = false
				f.from = f.pos
				f.s = 0.0
				f.lift_p = minf(p, 0.97) if not bool(f.step) else -1.0
		else:
			# a stride's swing ends on the clock (its stance begins as the leg's phase turns over); a step, or a swing
			# the horse stopped in, on its own time
			var on_clock := moving and not bool(f.step) and float(f.get("lift_p", -1.0)) >= 0.0
			var swing_s := (1.0 - duty) / hz if not bool(f.step) else STEP_S
			if on_clock:
				var lp := float(f.lift_p)
				f.s = 1.0 if wrapped else clampf((p - lp) / maxf(1.0 - lp, 0.03), float(f.s), 1.0)
			else:
				f.s = minf(1.0, float(f.s) + delta / maxf(swing_s, 0.05))
				f.lift_p = -1.0
			# where it lands: under its place when it lands, then half a stance ahead
			var left := 0.0 if float(f.s) >= 1.0 else ((1.0 - p) / hz if on_clock else (1.0 - float(f.s)) * swing_s)
			var to := home + _vel * left + _vel * stance_t * 0.5 if moving and not bool(f.step) else home
			to.y = actor.global_position.y
			f.to = to
			var e := smoothstep(0.0, 1.0, float(f.s))
			var gl := _gait_vec()
			var h := gl.dot(LIFT) * (1.0 if bool(_legs[leg].fore) else HIND_LIFT)
			if bool(f.step):
				h = 0.07
			f.pos = (f.from as Vector3).lerp(to, e) + Vector3.UP * h * sin(PI * float(f.s))
			if float(f.s) >= 1.0:
				f.stance = true
				f.step = false
				f.pos = to
				f.anchor = to
		if bool(f.stance):
			max_planted_slide = maxf(max_planted_slide, (f.pos as Vector3).distance_to(f.anchor))
		f.last_p = p


func _reset_pose() -> void:
	for i in _sk.get_bone_count():
		var rest := _sk.get_bone_rest(i)
		_sk.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		_sk.set_bone_pose_position(i, rest.origin)


## The legs onto their hooves (skeleton space; see the class notes).
func _solve_legs() -> void:
	var inv := _sk.global_transform.affine_inverse()
	for leg: String in LEGS:
		var L: Dictionary = _legs[leg]
		var f: Dictionary = _feet[leg]
		var b: Array = L.b
		var j: Array = L.joints
		var lens: Array = L.len
		var fore: bool = L.fore
		var sole := inv * (f.pos as Vector3)
		var fold := 0.0 if bool(f.stance) else sin(PI * float(f.s))
		var fold_deg: Vector2 = FORE_FOLD if fore else HIND_FOLD
		if bool(f.step):
			fold *= 0.4
		# the pastern as at rest (folded back in a swing), then the cannon: plumb at rest, folded in a swing
		var foot_rest := (j[4] as Vector3) - (j[3] as Vector3)
		var cannon_rest := (j[3] as Vector3) - (j[2] as Vector3)
		# a standing hoof left behind its hip or shoulder breaks over: the heel lifts, the fetlock rolls over the toe
		var behind := clampf(((j[0] as Vector3).z - sole.z - BREAKOVER_FROM_M) / BREAKOVER_M, 0.0, 1.0) \
			if bool(f.stance) else 0.0
		var fold_pastern := Basis(Vector3.RIGHT, deg_to_rad(fold_deg.y) * fold + deg_to_rad(BREAKOVER_DEG) * behind)
		var fetlock := sole - fold_pastern * foot_rest
		var cannon_dir := Basis(Vector3.RIGHT, deg_to_rad(fold_deg.x) * fold) * cannon_rest.normalized()
		var top: Vector3 = j[0]
		var slide := 0.0
		if fore:
			# the shoulder blade slides with the leg (the rig has no scapula bone: the upper bone's joint moves)
			slide = clampf((fetlock.z - top.z) * SCAPULA_SHARE, -SCAPULA_M, SCAPULA_M)
			top += Vector3(0.0, -absf(slide) * 0.3, slide)
		var reach := (float(lens[0]) + float(lens[1])) * 0.985
		var knee := fetlock - cannon_dir * float(lens[2])
		if knee.distance_to(top) > reach:
			# tilt the cannon toward the hip / shoulder as far as the leg must reach
			var toward := (top - fetlock).normalized()
			var lo := 0.0
			var hi := 1.0
			for _k in 8:
				var mid := (lo + hi) * 0.5
				var dirm := (-cannon_dir).slerp(toward, mid).normalized()
				if (fetlock + dirm * float(lens[2])).distance_to(top) > reach:
					lo = mid
				else:
					hi = mid
			knee = fetlock + (-cannon_dir).slerp(toward, hi).normalized() * float(lens[2])
		var solve := TipMatching.two_bone(top, knee, float(lens[0]), float(lens[1]), L.pole)
		var elbow: Vector3 = solve.elbow
		var knee_s: Vector3 = solve.end
		if bool(f.stance):
			max_reach_miss = maxf(max_reach_miss, knee_s.distance_to(knee))
		var pts := [top, elbow, knee_s, knee_s + (fetlock - knee), sole]
		var parent_basis := _global_basis(_sk.get_bone_parent(int(b[0])))
		if fore and int(b[0]) >= 0:
			var rest_pos := (_sk.get_bone_rest(int(b[0])) as Transform3D).origin
			_sk.set_bone_pose_position(int(b[0]), rest_pos + parent_basis.inverse() * Vector3(0.0, -absf(slide) * 0.3, slide))
		for k in 4:
			var bi: int = b[k]
			if bi < 0:
				continue
			var rest: Transform3D = _rest_global[bi]
			var d_rest := ((j[k + 1] as Vector3) - (j[k] as Vector3)).normalized()
			var d_new := ((pts[k + 1] as Vector3) - (pts[k] as Vector3)).normalized()
			var gb := PersonRig._arc(d_rest, d_new) * rest.basis
			var q := (parent_basis.inverse() * gb).orthonormalized().get_rotation_quaternion()
			if q.is_finite():
				_sk.set_bone_pose_rotation(bi, q)
			parent_basis = gb


## A bone's rest global basis (its parents at rest: the legs' parents, the pelvis and spine_02, are not turned).
func _global_basis(i: int) -> Basis:
	return (_rest_global[i] as Transform3D).basis if i >= 0 else Basis()


## The neck's nod, the brain's head pivot, the jaw and the tail.
func _pose_head_tail(s: Dictionary, delta: float, free: bool) -> void:
	var g := _gait_vec()
	var nod := 0.0
	if free and _speed > STAND_MPS:
		var twice := 1.0 - _w_gallop
		nod = deg_to_rad(g.dot(NOD_DEG)) * sin(TAU * (2.0 * twice + (1.0 - twice)) * _phase)
	var brain_pitch := 0.0
	if head != null:
		var rel := (_head_rest.inverse() * head.basis).get_euler()
		brain_pitch = rel.x
	if bool(s.get("lunging", false)):
		brain_pitch -= 0.12   # the neck stretched at the charge
	_turn_bone("neck", Basis(Vector3.RIGHT, nod * 0.6 - brain_pitch * 0.6))
	_turn_bone("head", Basis(Vector3.RIGHT, nod * 0.4 - brain_pitch * 0.4))
	_turn_bone("jaw", Basis(Vector3.RIGHT, deg_to_rad(JAW_GALLOP_DEG) * _w_gallop))
	var sway := tail.rotation.y if tail != null else 0.0
	_turn_bone("tail_01", Basis(Vector3.UP, -sway) * Basis(Vector3.RIGHT, deg_to_rad(TAIL_LIFT_DEG) * _w_gallop))
	_turn_bone("tail_02", Basis(Vector3.UP, -sway * 0.8))


## Turns bone `name` by `turn` (skeleton space, about its own joint) on top of its rest.
func _turn_bone(bone_name: String, turn: Basis) -> void:
	var i: int = _bones.get(bone_name, -1)
	if i < 0:
		return
	var parent := _sk.get_bone_global_pose(_sk.get_bone_parent(i)).basis.orthonormalized() if _sk.get_bone_parent(i) >= 0 else Basis()
	var rest_parent := _global_basis(_sk.get_bone_parent(i))
	var gb := turn * (parent * rest_parent.inverse()) * (_rest_global[i] as Transform3D).basis
	var q := (parent.inverse() * gb).orthonormalized().get_rotation_quaternion()
	if q.is_finite():
		_sk.set_bone_pose_rotation(i, q)


## The rider: the seated clip, the lean, the lance arm (see the class notes).
func _pose_rider(s: Dictionary, delta: float, dead: bool) -> void:
	var ap := _rider.player()
	if ap != null:
		ap.seek(0.0, true)
	var rsk := _rider.skeleton()
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", 0))
	var f := float(s.get("phase_fraction", 0.0))
	var charge := action != null and action.hit_shape == "body_sweep"
	var thrust := action != null and not charge and action.is_attack()
	var couch := 0.0
	if charge:
		couch = f if phase == ActionDef.Phase.WINDUP else (1.0 if phase == ActionDef.Phase.ACTIVE else 1.0 - f)
	elif bool(s.get("lunging", false)):
		couch = 1.0
	if dead:
		couch = 0.0
	_lance_w = move_toward(_lance_w, couch, delta * LANCE_RATE) if absf(couch - _lance_w) > 0.0 and not charge else couch
	var tw := 0.0
	if thrust:
		tw = -0.35 * f if phase == ActionDef.Phase.WINDUP else (1.0 if phase == ActionDef.Phase.ACTIVE else 1.0 - f)
	_thrust_w = lerpf(_thrust_w, tw, 1.0 - exp(-14.0 * delta))
	# the trunk leans with the gallop and the charge
	var lean := deg_to_rad(RIDER_LEAN_DEG) * maxf(_w_gallop, _lance_w * 0.7)
	if lean > 1e-4:
		for bn: String in ["spine_01", "spine_02", "spine_03"]:
			var i: int = _rider_bones.get(bn, -1)
			if i >= 0:
				var gp := rsk.get_bone_global_pose(i)
				PersonRig._set_global_rotation(rsk, i, Basis(Vector3.RIGHT, lean / 3.0) * gp.basis)
	# the lance's grip and direction in the rider's space (Visual's axes, the seat's origin)
	var grip := CARRY_GRIP.lerp(COUCH_GRIP, _lance_w)
	var dir := CARRY_DIR.normalized().slerp(COUCH_DIR.normalized(), _lance_w)
	if _thrust_w > 0.0:
		grip = grip.lerp(THRUST_GRIP, _thrust_w)
		dir = dir.slerp(THRUST_DIR.normalized(), _thrust_w)
	elif _thrust_w < 0.0:
		grip = grip + Vector3(0.0, 0.0, 0.25) * -_thrust_w / 0.35 * 0.35
	dir = dir.normalized()
	# the rider's space: the seat with Visual's axes (-Z front), so PersonRig's poles apply
	var seat_g := _rider.global_transform
	var space := Transform3D(seat_g.basis.orthonormalized() * Basis(Vector3.UP, PI), seat_g.origin)
	var m := space.affine_inverse() * rsk.global_transform
	var mi := m.affine_inverse()
	var hand_dir := (dir + Vector3(0.0, -0.35, 0.0)).normalized() if _lance_w > 0.5 else (Vector3(0.0, -0.3, -1.0)).normalized()
	PersonRig.solve_arm(rsk, _rider_bones, "r", m, mi, grip, hand_dir, 1.0, 1.0, _rider_grip.get("grip_r", PersonRig.FIST_LOCAL))
	var reins := REINS_GRIP + Vector3(0.0, 0.0, -0.08) * _lance_w
	PersonRig.solve_arm(rsk, _rider_bones, "l", m, mi, reins, REINS_HAND.normalized(), 1.0, 1.0,
		_rider_grip.get("grip_l", PersonRig.FIST_LOCAL * Vector3(-1.0, 1.0, 1.0)))
	# the lance on the fist, its +Y along the lance
	var hand := rsk.get_bone_global_pose(int(_rider_bones.hand_r))
	var fist := hand * (_rider_grip.get("grip_r", PersonRig.FIST_LOCAL) as Vector3)
	var y := (mi.basis * dir).normalized()
	var z := (hand.basis.y - y * y.dot(hand.basis.y))
	if z.length_squared() < 1e-6:
		z = Vector3.BACK - y * y.dot(Vector3.BACK)
	z = z.normalized()
	_lance_socket.transform = Transform3D(Basis(y.cross(z), y, z), fist)


# --------------------------------------------------------------------------- paint and reads

func _update_flash(delta: float) -> void:
	var active := _flash > 0.0 or _flash_applied > 0.0 or _tint_dirty
	super._update_flash(delta)
	if active and _mode == 1:
		var mats: Array = [_material, _gear_material]
		if _rider != null:
			mats.append(_rider.material)
		RigPaint.paint_shaders(mats.filter(func(x: Variant) -> bool: return x != null), _tint, _flash_applied, _flash_color)


func set_status_tint(color: Color) -> void:
	super.set_status_tint(color)


func horse() -> Node3D:
	return _horse


func skeleton() -> Skeleton3D:
	return _sk


func rider() -> PersonModel:
	return _rider


func lance_socket() -> Node3D:
	return _lance_socket


func material() -> ShaderMaterial:
	return _material


## The hooves in the world now and whether each stands (tests): {leg: [position, standing]}.
func hooves() -> Dictionary:
	var out := {}
	for leg: String in _feet:
		out[leg] = [(_feet[leg] as Dictionary).pos, (_feet[leg] as Dictionary).stance]
	return out


## A sole's place on the posed skeleton (world; tests: the solve reaches the planned hoof).
func posed_sole(leg: String) -> Vector3:
	var L: Dictionary = _legs.get(leg, {})
	if L.is_empty():
		return Vector3.INF
	var bi: int = (L.b as Array)[3]
	var j: Array = L.joints
	var g := _sk.get_bone_global_pose(bi)
	var rest: Transform3D = _rest_global[bi]
	return _sk.global_transform * (g * (rest.affine_inverse() * (j[4] as Vector3)))


## The gait's weights now: {"walk", "trot", "gallop", "duty", "hz"}.
func gait() -> Dictionary:
	var g := _gait_vec()
	return {"walk": g.x, "trot": g.y, "gallop": g.z, "duty": _duty(), "hz": stride_hz(_speed), "speed": _speed}


func lance_couched() -> float:
	return _lance_w
