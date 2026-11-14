class_name CrowdRenderer
extends Node3D
## Draws one formation's rank-and-file as a crowd (plan M6-M9 §2.10, decision 19; P30): one
## MultiMesh per pose (hold, brace, advance, flee) of the members' merged rig - each member scene's
## Visual/CrowdPoses/<pose> mesh, built by tools/builders/formations.gd - with one instance per
## member, its transform taken from the member every frame. A member is promoted to its own rig
## (Visual shown, its ActorRig processing) while it is within PROMOTE_M x the giant's distance
## scale of the giant, in an attack phase, staggered, held or dead (a falling corpse), at most
## MAX_PROMOTED at once - striking, staggered and held ones first, then the nearest; the dead are
## always shown and never count. A member whose scene has no crowd poses always draws its own rig.
## The banner is never part of the crowd: it keeps its rig and its flag (in the formation's colour)
## sways. Presentation only: it reads the members, never changes gameplay. The EncounterDirector
## makes one per formation (group crowd_renderers) and frees it with the formation; release_all()
## gives every member its rig back.
##
## Draw calls: one per pose in use (instances of one mesh and one material), so a formation of
## twenty costs about 2-4 plus its promoted rigs and its banner, instead of twenty rigs.

const GROUP := "crowd_renderers"
const POSES := ["hold", "brace", "advance", "flee"]
const POSES_PATH := "Visual/CrowdPoses"
## Promotion radius around the giant at the reference height (x the giant's height / 3.6576).
const PROMOTE_M := 20.0
const MAX_PROMOTED := 6
const REFERENCE_HEIGHT_M := 3.6576
## A member moving faster than this shows the advance pose.
const ADVANCE_SPEED_MPS := 0.3
## The banner's flag sways this much (radians) at this rate.
const FLAG_SWAY_RAD := 0.22
const FLAG_SWAY_HZ := 0.55

var formation: Formation = null
## Members drawing their own rig now (entity id -> true), and those in the crowd (entity id -> true).
var promoted := {}
var crowded := {}
## Instances drawn per pose at the last frame (tests, debug): pose -> count.
var pose_counts := {}

var _sets := {}           # mesh instance id -> {"pose", "mmi": MultiMeshInstance3D}
var _hidden := {}         # entity id -> EnemyActor whose rig this renderer hid
var _time := 0.0
var _flag_painted: Node = null


func _ready() -> void:
	add_to_group(GROUP)
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 10   # after the actors' rigs and the camera


func _exit_tree() -> void:
	release_all()


func _process(delta: float) -> void:
	_time += delta
	refresh()


## One frame of the crowd (also callable from tests): decides the promotions, hides and shows rigs,
## fills the multimeshes and sways the banner.
func refresh() -> void:
	if formation == null or formation.dissolved:
		release_all()
		_clear_sets()
		return
	var giant := _giant()
	var center := giant.global_position if giant != null else Vector3.INF
	var radius := PROMOTE_M * _distance_scale(giant)
	var urgent: Array = []
	var near: Array = []
	var crowd: Array = []
	var gone := {}
	for m in formation.members:
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		gone[m.entity_id] = true
		if not _has_poses(m) or _dead(m):
			_show(m)
			continue
		if _urgent(m):
			urgent.append(m)
		elif center != Vector3.INF and m.global_position.distance_to(center) <= radius:
			near.append(m)
		else:
			crowd.append(m)
	# Members that left the formation get their rigs back (M8 gate, F23: one freed meanwhile - a
	# despawned member - is only forgotten; a typed variable cannot hold a freed one).
	for id: String in _hidden.keys():
		if not gone.has(id):
			var a: Variant = _hidden[id]
			if is_instance_valid(a):
				_set_rig(a as EnemyActor, true)
			_hidden.erase(id)
	if center != Vector3.INF:
		urgent.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
			return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
		near.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
			return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	promoted.clear()
	crowded.clear()
	var slots := MAX_PROMOTED
	for list: Array in [urgent, near]:
		for m: EnemyActor in list:
			if slots > 0:
				slots -= 1
				_show(m)
				promoted[m.entity_id] = true
			else:
				crowd.append(m)
	var batches := {}   # mesh instance id -> {"mesh", "pose", "xforms": Array}
	for m: EnemyActor in crowd:
		var pose := pose_for(m)
		var mi := m.get_node_or_null(NodePath("%s/%s" % [POSES_PATH, pose])) as MeshInstance3D
		if mi == null or mi.mesh == null:
			_show(m)
			continue
		_hide(m)
		crowded[m.entity_id] = true
		var key := mi.mesh.get_instance_id()
		if not batches.has(key):
			batches[key] = {"mesh": mi.mesh, "pose": pose, "xforms": []}
		(batches[key].xforms as Array).append(m.global_transform)
	_fill(batches)
	_sway_banner()


## The pose a crowd member shows: flee (fleeing or routed), brace (its formation braced, or aware of
## the giant and standing: pikes levelled, shields up), advance (moving), else hold.
func pose_for(m: EnemyActor) -> String:
	var b := m.brain
	if b != null and b.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]:
		return "flee"
	var moving := Vector2(m.velocity.x, m.velocity.z).length() > ADVANCE_SPEED_MPS
	if formation != null and (formation.state == "braced" or (formation.aware and not moving)):
		return "brace"
	if moving:
		return "advance"
	return "hold"


## Every member drawn by this renderer gets its rig back (the formation dissolved, or tests).
func release_all() -> void:
	for id: String in _hidden.keys():
		var a: Variant = _hidden[id]
		if is_instance_valid(a):
			_set_rig(a as EnemyActor, true)
	_hidden.clear()
	crowded.clear()
	promoted.clear()


## Instances drawn now (all poses).
func instance_count() -> int:
	var n := 0
	for c: Variant in pose_counts.values():
		n += int(c)
	return n


func _fill(batches: Dictionary) -> void:
	pose_counts.clear()
	for p: String in POSES:
		pose_counts[p] = 0
	for key: Variant in _sets.keys():
		if not batches.has(key):
			var s: Dictionary = _sets[key]
			(s.mmi as MultiMeshInstance3D).multimesh.visible_instance_count = 0
			(s.mmi as MultiMeshInstance3D).visible = false
	for key: Variant in batches.keys():
		var b: Dictionary = batches[key]
		var xforms: Array = b.xforms
		var s: Dictionary = _sets.get(key, {})
		if s.is_empty():
			s = {"pose": b.pose, "mmi": _make_set(b.mesh, str(b.pose))}
			_sets[key] = s
		var mmi: MultiMeshInstance3D = s.mmi
		var mm := mmi.multimesh
		if mm.instance_count < xforms.size():
			mm.instance_count = maxi(xforms.size(), maxi(8, formation.slot_count() if formation != null else 8))
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		mm.visible_instance_count = xforms.size()
		mmi.visible = xforms.size() > 0
		pose_counts[b.pose] = int(pose_counts.get(b.pose, 0)) + xforms.size()


## One MultiMesh of `mesh` (a CrowdPoses mesh: the rig material is on its surface, shared by every
## formation of the archetype).
func _make_set(mesh: Mesh, pose: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(8, formation.slot_count() if formation != null else 8)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crowd_%s_%d" % [pose, _sets.size()]
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


func _clear_sets() -> void:
	for s: Dictionary in _sets.values():
		var mmi: MultiMeshInstance3D = s.mmi
		if is_instance_valid(mmi):
			mmi.multimesh.visible_instance_count = 0
			mmi.visible = false
	pose_counts.clear()


## A member's own rig is shown again (promoted, dead, without crowd poses, or left).
func _show(m: EnemyActor) -> void:
	if _hidden.has(m.entity_id):
		_set_rig(m, true)
		_hidden.erase(m.entity_id)


func _hide(m: EnemyActor) -> void:
	if not _hidden.has(m.entity_id):
		_hidden[m.entity_id] = m
		_set_rig(m, false)


## Shows (or hides) a member's Visual and runs (or stops) its rig's per-frame posing.
static func _set_rig(m: EnemyActor, on: bool) -> void:
	var visual := m.get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	visual.visible = on
	visual.set_process(on)


func _has_poses(m: EnemyActor) -> bool:
	return m.get_node_or_null(NodePath(POSES_PATH)) != null


static func _dead(m: EnemyActor) -> bool:
	return m.entity == null or m.entity.combatant == null or not m.entity.is_alive()


## Striking (any phase of an action), staggered or held: it must show its own rig.
static func _urgent(m: EnemyActor) -> bool:
	if m.is_held():
		return true
	var c := m.controller
	return c != null and (c.action != null or c.state == CombatController.State.STAGGERED)


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
