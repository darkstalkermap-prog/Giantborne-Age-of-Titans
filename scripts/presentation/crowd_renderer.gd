class_name CrowdRenderer
extends Node3D
## Draws the people who are not skinned as a crowd (plan M6-M9 §2.10, decision 19; P30; P60: plan M11 §2.9, probe
## 8). PersonRig decides every person's level each frame (skinned, crowd, far, corpse; its _allocate); a renderer
## draws the crowd, far and corpse levels of the people it covers as MultiMesh instances - one MultiMesh per person
## role and pose (hold, brace, advance, flee, corpse, and "far": P59's crowd-pose meshes and far mesh, the role's
## crowd material) and one per piece of gear and pose (a pike, a sword, a shield, a quiver in the pose's hands) -
## each instance carrying the person's palette row, its hit flash and its faction's row in the custom data and its
## status tint in the instance colour (person_crowd.gdshader). So a formation of forty costs a few draw calls
## however many are drawn, and a flash or a tint reaches every member.
##
## Two kinds of renderer: one per formation (the EncounterDirector makes one, group crowd_renderers, and frees it
## with the formation), covering its members, in its pose (pose_for: flee, brace, advance, hold by the formation's
## state); and one shared renderer of the loners (`loners`: PersonRig makes it with the first person it draws),
## covering every person no other renderer drew this frame, in the pose its own state gives. A member whose Visual
## is not a PersonRig always draws its own rig. The banner keeps its pole and flag (its flag, in the formation's
## colour, sways); its body is a person like any other.
##
## Presentation only: it reads the members, never changes gameplay. Headless (PersonRig.layers_enabled() off)
## nothing is instanced: the members' rigs keep posing their empty pivots.

const GROUP := "crowd_renderers"
const POSES := ["hold", "brace", "advance", "flee", "corpse", "far"]
const POSES_PATH := "Visual/CrowdPoses"
## The giant's distance scale's reference height (the giant's height / this, 1 .. 5.2).
const REFERENCE_HEIGHT_M := 3.6576
## A member moving faster than this shows the advance pose.
const ADVANCE_SPEED_MPS := 0.3
## The banner's flag sways this much (radians) at this rate.
const FLAG_SWAY_RAD := 0.22
const FLAG_SWAY_HZ := 0.55
## How a piece of gear lies in a crowd pose (the pose's own frame: +Z the person's front): its direction, and
## whether it is drawn at all (a fleeing man drops his pike from view; a corpse's and a far mesh's gear is not drawn).
const GEAR_DIRS := {
	"spear": {"hold": Vector3(0.0, 1.0, 0.12), "brace": Vector3(0.0, -0.08, 1.0), "advance": Vector3(0.0, 1.0, 0.35)},
	"staff": {"hold": Vector3(0.0, 1.0, 0.1), "brace": Vector3(0.0, 1.0, 0.2), "advance": Vector3(0.0, 1.0, 0.2)},
	"bow": {"hold": Vector3(0.0, 1.0, 0.05), "brace": Vector3(0.0, 1.0, 0.1), "advance": Vector3(0.0, 1.0, 0.1)},
	"sword": {"hold": Vector3(0.05, -0.75, 0.65), "brace": Vector3(0.0, 0.45, 1.0), "advance": Vector3(0.0, -0.6, 0.8)},
	"hammer": {"hold": Vector3(0.05, -0.8, 0.6), "brace": Vector3(0.0, 0.3, 1.0), "advance": Vector3(0.0, -0.7, 0.7)},
}
const WORN_GEAR := ["shield", "quiver"]

## The formation drawn (null for the loners' renderer).
var formation: Formation = null
## The shared renderer of every person no formation's renderer drew.
var loners := false
## Members skinned now (entity id -> true), and those drawn as instances (entity id -> true).
var promoted := {}
var crowded := {}
## Instances drawn per pose at the last frame (tests, debug): pose -> count.
var pose_counts := {}
## What each person drawn at the last frame was given (tests, debug: the dummy renderer keeps no instance data):
## entity id -> [the set's key, the custom data].
var drawn := {}

var _sets := {}           # "<person role>|<pose>|<piece>" -> MultiMeshInstance3D
var _time := 0.0
var _flag_painted: Node = null
static var _gear_xf := {}  # "<role>|<pose>|<piece>" -> Transform3D (the pose's frame)
static var _roles := {}    # "<role>|<person role>" -> _role_sets()


## The caches go with the process's people (PersonModel.drop_all at exit).
static func drop_caches() -> void:
	_roles.clear()
	_gear_xf.clear()


func _ready() -> void:
	add_to_group(GROUP)
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 11 if loners else 10   # after the actors' rigs; the loners after the formations


func _exit_tree() -> void:
	release_all()


func _process(delta: float) -> void:
	_time += delta
	refresh()


## One frame of the crowd (also callable from tests): fills the multimeshes from the people's levels and sways
## the banner.
func refresh() -> void:
	promoted.clear()
	crowded.clear()
	drawn.clear()
	if not loners and (formation == null or formation.dissolved):
		_clear_sets()
		return
	var frame := Engine.get_process_frames()
	var my_id := get_instance_id()
	var batches := {}   # set key -> {"mesh", "material", "pose", "xforms": [], "custom": [], "colors": []}
	var members: Array = PersonRig.rigs() if loners else formation.members.duplicate()
	if not loners and formation.banner_alive():
		members.append(formation.banner)
	for item: Variant in members:
		if not is_instance_valid(item):
			continue   # (M8 gate, F23: a member freed meanwhile - a despawned one - is only skipped)
		var rig: PersonRig = null
		var m: Node3D = null
		if loners:
			rig = item as PersonRig
			m = rig.actor
		else:
			m = item as Node3D
			rig = m.get_node_or_null("Visual") as PersonRig if m != null else null
		if m == null or rig == null or not is_instance_valid(m) or not rig.is_inside_tree():
			continue
		var lvl := rig.level
		if lvl == PersonRig.Level.SKINNED:
			promoted[rig.entity_id] = true
			continue
		if lvl != PersonRig.Level.CROWD and lvl != PersonRig.Level.FAR and lvl != PersonRig.Level.CORPSE:
			continue
		if rig.drawn_frame == frame and rig.drawn_by != my_id:
			continue   # another renderer drew it this frame
		var pose := "corpse" if lvl == PersonRig.Level.CORPSE else ("far" if lvl == PersonRig.Level.FAR else
			(pose_for(m as EnemyActor) if m is EnemyActor else "hold"))
		if _add(batches, rig, pose):
			drawn[rig.entity_id] = [rig.crowd_person_role + "|" + pose + "|", rig.custom_data()]
			rig.drawn_frame = frame
			rig.drawn_by = my_id
			crowded[rig.entity_id] = true
	_fill(batches)
	_sway_banner()


## Adds one person (and its gear) to the batches; false when its role has no mesh for the pose.
func _add(batches: Dictionary, rig: PersonRig, pose: String) -> bool:
	var role := rig.crowd_role
	var person_role := rig.crowd_person_role
	var spec: Dictionary = _role_sets(role, person_role)
	if spec.is_empty():
		return false
	var mesh: Mesh = spec.far if pose == "far" else (spec.poses as Dictionary).get(pose)
	if mesh == null:
		return false
	var xf := rig.crowd_transform()
	var custom := rig.custom_data()
	var color := rig.tint_color()
	_batch(batches, str((spec.keys as Dictionary)[pose]), mesh, spec.material, pose, xf, custom, color)
	if pose == "far" or pose == "corpse" or pose == "flee":
		return true
	var gear: Array = rig.crowd_cache.get(pose, [])
	if not rig.crowd_cache.has(pose):
		for p: Variant in rig.look.get("gear", []):
			var piece := str(p)
			var gxf := gear_transform(role, pose, piece)
			var gmesh := PersonModel.gear_mesh(piece)
			if gmesh != null and gxf != Transform3D():
				gear.append([gmesh, gxf, "%s|%s|%s" % [person_role, pose, piece]])
		rig.crowd_cache[pose] = gear
	for g: Array in gear:
		_batch(batches, g[2], g[0], spec.gear_material, pose, xf * (g[1] as Transform3D), custom, color)
	return true


## A role's meshes, materials and set keys, looked up once (the crowd draws every frame).
func _role_sets(role: String, person_role: String) -> Dictionary:
	var k := role + "|" + person_role
	if _roles.has(k):
		return _roles[k]
	var r := PersonModel.role_data(role)
	var out := {}
	if not r.is_empty():
		var keys := {}
		for pose: String in POSES:
			keys[pose] = "%s|%s|" % [person_role, pose]
		out = {"far": r.far, "poses": r.poses, "keys": keys, "material": PersonModel.crowd_material(person_role),
			"gear_material": PersonModel.crowd_material(person_role, true)}
	_roles[k] = out
	return out


static func _batch(batches: Dictionary, key: String, mesh: Mesh, mat: Material, pose: String, xf: Transform3D,
		custom: Color, color: Color) -> void:
	if not batches.has(key):
		batches[key] = {"mesh": mesh, "material": mat, "pose": pose, "xforms": [], "custom": [], "colors": [],
			"gear": not key.ends_with("|")}
	var b: Dictionary = batches[key]
	(b.xforms as Array).append(xf)
	(b.custom as Array).append(custom)
	(b.colors as Array).append(color)


## Where a piece of gear lies in a crowd pose of `role` (the pose mesh's frame, +Z the front): a weapon in the
## right hand along GEAR_DIRS (fitted as the skinned person's: PersonRig.GEAR_FIT), a shield on the left forearm
## facing out, a quiver on the back. Transform3D() when the piece is not drawn in that pose.
static func gear_transform(role: String, pose: String, piece: String) -> Transform3D:
	var key := "%s|%s|%s" % [role, pose, piece]
	if _gear_xf.has(key):
		return _gear_xf[key]
	var xf := Transform3D()
	if piece == "shield":
		var a := PersonModel.pose_joint(role, pose, "lowerarm_l")
		var b := PersonModel.pose_joint(role, pose, "hand_l")
		var chest := PersonModel.pose_joint(role, pose, "spine_03")
		if a != Vector3.INF and b != Vector3.INF and chest != Vector3.INF:
			var along := (b - a).normalized()
			var centre := a.lerp(b, 0.55)
			var out := centre - chest
			out = (out - along * along.dot(out)).normalized()
			xf = Transform3D(Basis((-along).cross(out).normalized(), -along, out), centre + out * 0.07)
	elif piece == "quiver":
		var sp := PersonModel.pose_joint(role, pose, "spine_03")
		var nk := PersonModel.pose_joint(role, pose, "neck_01")
		if sp != Vector3.INF and nk != Vector3.INF:
			var up := (nk - sp).normalized()
			var behind := Vector3(0.0, 0.0, -1.0)
			behind = (behind - up * up.dot(behind)).normalized()
			var yb := (Basis(behind, deg_to_rad(20.0)) * up).normalized()
			xf = Transform3D(Basis(yb.cross(behind).normalized(), yb, behind), sp + behind * 0.16 + Vector3(-0.08, -0.05, 0.0))
	elif GEAR_DIRS.has(piece) and (GEAR_DIRS[piece] as Dictionary).has(pose):
		var hand := PersonModel.pose_joint(role, pose, "hand_r")
		var lo := PersonModel.pose_joint(role, pose, "lowerarm_r")
		if hand != Vector3.INF and lo != Vector3.INF:
			var y: Vector3 = (GEAR_DIRS[piece][pose] as Vector3).normalized()
			var fore := (hand - lo).normalized()
			var fist := hand + fore * PersonRig.FIST_LOCAL.y
			var z := fore - y * y.dot(fore)
			if z.length_squared() < 1e-6:
				z = Vector3.BACK - y * y.dot(Vector3.BACK)
			z = z.normalized()
			var fit: Dictionary = PersonRig.GEAR_FIT.get(piece, {})
			var s := float(fit.get("scale", 1.0))
			xf = Transform3D(Basis(y.cross(z), y, z) * Basis.from_scale(Vector3(1.0, s, 1.0)),
				fist + y * float(fit.get("shift", 0.0)))
	_gear_xf[key] = xf
	return xf


## The pose a crowd member shows: flee (fleeing or routed), brace (its formation braced, or aware of the giant and
## standing: pikes levelled, shields up; a loner guarding), advance (moving), else hold.
func pose_for(m: EnemyActor) -> String:
	var b := m.brain
	if b != null and b.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]:
		return "flee"
	var moving := Vector2(m.velocity.x, m.velocity.z).length() > ADVANCE_SPEED_MPS
	if formation != null and (formation.state == "braced" or (formation.aware and not moving)):
		return "brace"
	if formation == null and not moving and m.is_guarding():
		return "brace"
	if moving:
		return "advance"
	return "hold"


## Nothing drawn any more (the formation dissolved, or tests).
func release_all() -> void:
	crowded.clear()
	promoted.clear()
	_clear_sets()


## Instances drawn now (all poses, the bodies only).
func instance_count() -> int:
	var n := 0
	for c: Variant in pose_counts.values():
		n += int(c)
	return n


## Draw calls the crowd costs now: one per MultiMesh with an instance shown.
func draw_sets() -> int:
	var n := 0
	for mmi: Variant in _sets.values():
		if is_instance_valid(mmi) and (mmi as MultiMeshInstance3D).visible:
			n += 1
	return n


func _fill(batches: Dictionary) -> void:
	pose_counts.clear()
	for p: String in POSES:
		pose_counts[p] = 0
	for key: Variant in _sets.keys():
		if not batches.has(key):
			var old: MultiMeshInstance3D = _sets[key]
			old.multimesh.visible_instance_count = 0
			old.visible = false
	var total := 0
	for key: Variant in batches.keys():
		var b: Dictionary = batches[key]
		var xforms: Array = b.xforms
		var mmi: MultiMeshInstance3D = _sets.get(key)
		if mmi == null:
			mmi = _make_set(b.mesh, b.material, str(key))
			_sets[key] = mmi
		var mm := mmi.multimesh
		if mm.instance_count < xforms.size():
			mm.instance_count = maxi(xforms.size(), maxi(8, formation.slot_count() + 1 if formation != null else 16))
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_custom_data(i, b.custom[i])
			mm.set_instance_color(i, b.colors[i])
		mm.visible_instance_count = xforms.size()
		mmi.visible = xforms.size() > 0
		if not bool(b.gear):
			pose_counts[b.pose] = int(pose_counts.get(b.pose, 0)) + xforms.size()
			total += xforms.size()
	if total > 0:
		PersonRig.totals.crowd_frames = int(PersonRig.totals.crowd_frames) + 1
		PersonRig.totals.crowd_instances = int(PersonRig.totals.crowd_instances) + total
		PersonRig.totals.crowd_instances_max = maxi(int(PersonRig.totals.crowd_instances_max), total)
		PersonRig.totals.far_instances = int(PersonRig.totals.far_instances) + int(pose_counts.get("far", 0))


## One MultiMesh of `mesh` with `material` (per-instance colours and custom data).
func _make_set(mesh: Mesh, material: Material, key: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = maxi(8, formation.slot_count() + 1 if formation != null else 16)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crowd_%s" % key.replace("|", "_").replace(".", "_")
	mmi.multimesh = mm
	mmi.material_override = material
	# the crowd casts shadows by its bodies only (its gear is thin)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key.get_slice("|", 2) != "" \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	return mmi


func _clear_sets() -> void:
	for s: Variant in _sets.values():
		var mmi := s as MultiMeshInstance3D
		if is_instance_valid(mmi):
			mmi.multimesh.visible_instance_count = 0
			mmi.visible = false
	pose_counts.clear()


func _giant() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null


## The giant's distance scale: its height over the reference height, 1 .. 5.2 (as the audio's).
static func _distance_scale(giant: Node3D) -> float:
	if giant == null:
		return 1.0
	var e: Variant = giant.get("entity")
	if e is CombatEntity and (e as CombatEntity).combatant != null:
		return clampf((e as CombatEntity).combatant.height_m / REFERENCE_HEIGHT_M, 1.0, 5.2)
	return 1.0


## The banner's flag (Visual/Body/FlagPivot) sways, painted once in the formation's colour.
func _sway_banner() -> void:
	if formation == null or not formation.banner_alive():
		return
	var pivot := formation.banner.get_node_or_null("Visual/Body/FlagPivot") as Node3D
	if pivot == null:
		return
	pivot.rotation.y = sin(_time * TAU * FLAG_SWAY_HZ + float(absi(hash(formation.id)) % 100) * 0.1) * FLAG_SWAY_RAD
	if _flag_painted != pivot:
		_flag_painted = pivot
		var flag := pivot.get_node_or_null("Flag") as MeshInstance3D
		if flag != null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = formation.banner_color
			mat.roughness = 0.9
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			flag.material_override = mat
