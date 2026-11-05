class_name CosmeticField
extends Node3D
## Batched cosmetic dressing (P15, plan §4.3, decision 23): the bushes, banners and barley
## sheaves of one Valley district, drawn as three MultiMeshes (spheres, boxes, cones) with
## per-instance colours, so forty props cost three draw calls instead of a hundred and twenty
## (P14 measured the Valley far over its draw-call budget; FOLLOWUPS: "P15 must not add unbatched
## dressing"). Each item still reacts like a CosmeticProp, which the field mirrors:
##   * Events.area_pulse whose radius reaches it (Heavy Footfall, Thunder Roar, splashes): a wobble;
##   * Events.ability_effect "sector" (within the radius and the arc) and "roar": a wobble;
##   * an actor (the giant, enemies, NPCs) coming within the item's react radius, checked at 5 Hz:
##     a wobble, or a 4 s flatten when a stage-2+ giant steps into it.
## No collision, no CombatEntity, never saved. Item kinds name their prop record (react radius):
## bush -> prop.bush, banner -> prop.banner, sheaf -> prop.barley_sheaf.
##
## The builder (tools/builders/valley.gd) writes `kinds`, `transforms` (each item's place, yaw and
## scale) and `tints` (a banner's cloth colour; a zero alpha keeps the default); the MultiMeshes
## are made in _ready from the shape templates below. Group "cosmetic_fields".

const GROUP := "cosmetic_fields"
const CHECK_TICKS := 12             ## 5 Hz at the 60 Hz Sim (CosmeticProp's rate)
const HOOK_ORDER := 220             ## POST_RESOLVE, after the gameplay hooks
const FLATTEN_S := 4.0
const FLATTEN_IN_S := 0.12
const FLATTEN_OUT_S := 0.5
const FLATTEN_SCALE := Vector3(1.15, 0.25, 1.15)
const FLATTEN_STAGE := 2
const PULSE_MARGIN_M := 0.4
const WOBBLE_S := 0.56
const ACTOR_GROUPS := ["player", "enemies", "npcs"]
## Beyond this distance the dressing is not drawn (it is small; the fog starts at 120 m).
const VISIBILITY_END_M := 140.0
const RECORDS := {"bush": "prop.bush", "banner": "prop.banner", "sheaf": "prop.barley_sheaf"}
const DEFAULT_RADIUS_M := 1.5

const LEAVES := Color(0.25, 0.42, 0.20)
const LEAVES_DARK := Color(0.17, 0.32, 0.16)
const WOOD := Color(0.36, 0.25, 0.15)
const CLOTH := Color(0.62, 0.14, 0.13)
const STRAW := Color(0.80, 0.68, 0.34)
const STRAW_BAND := Color(0.55, 0.42, 0.20)

## The parts of each kind: [mesh ("sphere" | "box" | "cone"), local transform (unit mesh scaled),
## colour ("cloth" = the item's tint)].
static var TEMPLATES := {
	"bush": [
		["sphere", Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3(0, 0.6, 0)), LEAVES],
		["sphere", Transform3D(Basis.from_scale(Vector3.ONE * 1.1), Vector3(0.55, 0.5, 0.2)), LEAVES_DARK],
		["sphere", Transform3D(Basis.from_scale(Vector3.ONE * 1.0), Vector3(-0.5, 0.45, -0.25)), LEAVES],
	],
	"banner": [
		["box", Transform3D(Basis.from_scale(Vector3(0.16, 4.2, 0.16)), Vector3(0, 2.1, 0)), WOOD],
		["box", Transform3D(Basis.from_scale(Vector3(1.5, 0.1, 0.1)), Vector3(0, 4.0, 0)), WOOD],
		["box", Transform3D(Basis.from_scale(Vector3(1.3, 2.2, 0.05)), Vector3(0, 2.85, -0.08)), "cloth"],
	],
	"sheaf": [
		["cone", Transform3D(Basis.from_scale(Vector3(0.9, 1.4, 0.9)), Vector3(0, 0.7, 0)), STRAW],
		["box", Transform3D(Basis.from_scale(Vector3(0.62, 0.12, 0.62)), Vector3(0, 0.55, 0)), STRAW_BAND],
	],
}
const MESHES := ["sphere", "box", "cone"]

## One per item (the builder's).
@export var kinds := PackedStringArray()
@export var transforms: Array[Transform3D] = []
@export var tints := PackedColorArray()

## Reactions per item (one per tick at most), and in all.
var react_counts := PackedInt32Array()
var react_count := 0
## The MultiMesh of each mesh kind ("sphere", "box", "cone"); absent when no item uses it.
var multimeshes := {}

var _radii := PackedFloat32Array()
var _flat_left := PackedFloat32Array()      ## > 0 while flattened (s left, including the way back)
var _wobble_t := PackedFloat32Array()       ## < 0: not wobbling
var _wobble_axis: Array[Vector3] = []
var _wobble_amp := PackedFloat32Array()
var _last_react_tick := PackedInt32Array()
var _parts: Dictionary = {}                 ## mesh -> [[item, local Transform3D, Color], ...]
var _buffers: Dictionary = {}               ## mesh -> PackedFloat32Array
var _inside := {}                            ## actor instance id -> {item index: true}
var _bounds := Rect2()
var _max_radius := 0.0
var _phase := 0
var _dirty := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _ready() -> void:
	var n := item_count()
	react_counts.resize(n)
	_radii.resize(n)
	_flat_left.resize(n)
	_wobble_t.resize(n)
	_wobble_amp.resize(n)
	_last_react_tick.resize(n)
	_wobble_axis.resize(n)
	for i in n:
		_radii[i] = react_radius(kinds[i])
		_max_radius = maxf(_max_radius, _radii[i])
		_wobble_t[i] = -1.0
		_last_react_tick[i] = -1
		var p := transforms[i].origin
		_bounds = Rect2(Vector2(p.x, p.z), Vector2.ZERO) if i == 0 else _bounds.expand(Vector2(p.x, p.z))
	_build_meshes()
	_phase = absi(hash(str(get_path()))) % CHECK_TICKS
	Events.area_pulse.connect(_on_area_pulse)
	Events.ability_effect.connect(_on_ability_effect)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_sim_tick, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


func item_count() -> int:
	return mini(kinds.size(), transforms.size())


## The react radius of a kind: its prop record's react_radius_m.
static func react_radius(kind: String) -> float:
	var rec := GameData.get_record(str(RECORDS.get(kind, "")))
	return float(rec.get("react_radius_m", DEFAULT_RADIUS_M))


## The world position of item `i` (the field sits at the level's origin; its transforms are in
## its own space).
func item_position(i: int) -> Vector3:
	return global_transform * transforms[i].origin


func is_flattened(i: int) -> bool:
	return _flat_left[i] > 0.0


func is_wobbling(i: int) -> bool:
	return _wobble_t[i] >= 0.0


## The items within `radius` m (horizontally) of `pos`.
func items_near(pos: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in item_count():
		if _flat(item_position(i), pos) <= radius:
			out.append(i)
	return out


# --------------------------------------------------------------------------- reactions

## One reaction of item `i` to something at `source` (world position): strength >= 1 flattens it
## for FLATTEN_S, less wobbles it. Counts once per tick.
func react(i: int, source: Vector3, strength: float) -> void:
	if i < 0 or i >= item_count() or Sim.tick == _last_react_tick[i]:
		return
	_last_react_tick[i] = Sim.tick
	react_counts[i] += 1
	react_count += 1
	if strength >= 1.0:
		_flat_left[i] = FLATTEN_S + FLATTEN_OUT_S
		_wobble_t[i] = -1.0
	elif _flat_left[i] <= 0.0:
		var away := item_position(i) - source
		away.y = 0.0
		var axis := Vector3.UP.cross(away.normalized()) if away.length_squared() > 1e-6 else Vector3.RIGHT
		_wobble_axis[i] = (global_basis.inverse() * axis).normalized()
		_wobble_amp[i] = deg_to_rad(10.0 + 14.0 * clampf(strength, 0.0, 1.0))
		_wobble_t[i] = 0.0
	_dirty = true


func _on_area_pulse(_tick: int, _actor_id: String, _action_id: String, center: Vector3, radius: float) -> void:
	if not is_inside_tree() or not _near_bounds(center, radius + PULSE_MARGIN_M):
		return
	for i in item_count():
		if _flat(center, item_position(i)) <= radius + PULSE_MARGIN_M:
			react(i, center, 0.6)


func _on_ability_effect(_tick: int, _actor_id: String, _action_id: String, kind: String, center: Vector3,
		radius: float, yaw: float, arc_deg: float) -> void:
	if not is_inside_tree() or not kind in ["sector", "roar"] or not _near_bounds(center, radius + PULSE_MARGIN_M):
		return
	for i in item_count():
		var to := item_position(i) - center
		to.y = 0.0
		if to.length() > radius + PULSE_MARGIN_M:
			continue
		if kind == "sector" and to.length() > 1e-3 \
				and absf(angle_difference(yaw, TargetingRules.yaw_of(to))) > deg_to_rad(arc_deg * 0.5):
			continue
		react(i, center, 0.7)


## Actors entering an item's reach, checked every CHECK_TICKS ticks.
func _on_sim_tick(tick: int) -> void:
	if (tick + _phase) % CHECK_TICKS != 0 or not is_inside_tree():
		return
	var seen := {}
	for group: String in ACTOR_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var actor := node as Node3D
			if actor == null or not actor.is_inside_tree():
				continue
			var r := CosmeticProp.actor_radius(actor)
			if not _near_bounds(actor.global_position, _max_radius + r):
				continue
			var key := actor.get_instance_id()
			var was: Dictionary = _inside.get(key, {})
			var now := {}
			for i in item_count():
				if _flat(actor.global_position, item_position(i)) > _radii[i] + r:
					continue
				now[i] = true
				if not was.has(i):
					react(i, actor.global_position, 1.0 if CosmeticProp.flattens(actor) else 0.5)
			if not now.is_empty():
				seen[key] = now
	_inside = seen


func _near_bounds(p: Vector3, margin: float) -> bool:
	var local := global_transform.affine_inverse() * p
	return _bounds.grow(margin).has_point(Vector2(local.x, local.z))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- presentation

func _process(delta: float) -> void:
	if not _dirty:
		return
	var animating := false
	for i in item_count():
		var moved := false
		if _flat_left[i] > 0.0:
			_flat_left[i] = maxf(0.0, _flat_left[i] - delta)
			moved = true
		if _wobble_t[i] >= 0.0:
			_wobble_t[i] += delta
			if _wobble_t[i] > WOBBLE_S:
				_wobble_t[i] = -1.0
			moved = true
		if moved:
			_write_item(i)
			animating = animating or _flat_left[i] > 0.0 or _wobble_t[i] >= 0.0
	_upload()
	_dirty = animating


## The item's current transform: its place, then the wobble tilt or the flatten squash.
func item_transform(i: int) -> Transform3D:
	var t := transforms[i]
	if _flat_left[i] > 0.0:
		var shown := FLATTEN_S + FLATTEN_OUT_S - _flat_left[i]
		var f := 1.0
		if shown < FLATTEN_IN_S:
			f = shown / FLATTEN_IN_S
		elif _flat_left[i] < FLATTEN_OUT_S:
			f = _flat_left[i] / FLATTEN_OUT_S
		return t * Transform3D(Basis.from_scale(Vector3.ONE.lerp(FLATTEN_SCALE, clampf(f, 0.0, 1.0))), Vector3.ZERO)
	if _wobble_t[i] >= 0.0:
		var angle := _wobble_curve(_wobble_t[i]) * _wobble_amp[i]
		return t * Transform3D(Basis(_wobble_axis[i], angle), Vector3.ZERO)
	return t


## CosmeticProp's wobble: out to +1, back to -0.5, then +0.2, then rest (0.56 s).
static func _wobble_curve(t: float) -> float:
	var keys := [[0.0, 0.0], [0.08, 1.0], [0.24, -0.5], [0.38, 0.2], [0.56, 0.0]]
	for k in keys.size() - 1:
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if t <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / (float(b[0]) - float(a[0])))
	return 0.0


func _build_meshes() -> void:
	for mesh_kind: String in MESHES:
		_parts[mesh_kind] = []
	for i in item_count():
		var tmpl: Array = TEMPLATES.get(kinds[i], [])
		for part: Array in tmpl:
			var c: Variant = part[2]
			var color: Color = c if c is Color else (tints[i] if i < tints.size() and tints[i].a > 0.0 else CLOTH)
			(_parts[part[0]] as Array).append([i, part[1], color])
	var meshes := _unit_meshes()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	for mesh_kind: String in MESHES:
		var parts: Array = _parts[mesh_kind]
		if parts.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[mesh_kind]
		mm.instance_count = parts.size()
		var buf := PackedFloat32Array()
		buf.resize(parts.size() * 16)
		_buffers[mesh_kind] = buf
		for k in parts.size():
			_write_part(mesh_kind, k)
		mm.buffer = _buffers[mesh_kind]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = mesh_kind.capitalize() + "s"
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = VISIBILITY_END_M
		add_child(mmi)
		multimeshes[mesh_kind] = mm


func _write_item(i: int) -> void:
	for mesh_kind: String in _parts:
		var parts: Array = _parts[mesh_kind]
		for k in parts.size():
			if int(parts[k][0]) == i:
				_write_part(mesh_kind, k)


## Part k of a mesh kind into its buffer: [3 x 4 transform rows, colour].
func _write_part(mesh_kind: String, k: int) -> void:
	var part: Array = _parts[mesh_kind][k]
	var t: Transform3D = item_transform(int(part[0])) * (part[1] as Transform3D)
	var c: Color = part[2]
	var b := t.basis
	var o := t.origin
	var buf: PackedFloat32Array = _buffers[mesh_kind]
	var at := k * 16
	for v: float in [b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, c.r, c.g, c.b, c.a]:
		buf[at] = v
		at += 1
	_buffers[mesh_kind] = buf


func _upload() -> void:
	for mesh_kind: String in multimeshes:
		(multimeshes[mesh_kind] as MultiMesh).buffer = _buffers[mesh_kind]


static func _unit_meshes() -> Dictionary:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	return {"sphere": sphere, "box": box, "cone": cone}


## The current transform of the parts' instance for tests and tools: the CPU copy of the buffers
## (the headless renderer keeps no MultiMesh transforms).
func part_transform(mesh_kind: String, k: int) -> Transform3D:
	var buf: PackedFloat32Array = _buffers.get(mesh_kind, PackedFloat32Array())
	var at := k * 16
	if at + 12 > buf.size():
		return Transform3D()
	return Transform3D(Basis(Vector3(buf[at], buf[at + 4], buf[at + 8]), Vector3(buf[at + 1], buf[at + 5], buf[at + 9]),
		Vector3(buf[at + 2], buf[at + 6], buf[at + 10])), Vector3(buf[at + 3], buf[at + 7], buf[at + 11]))


## The parts of item `i`: [[mesh kind, part index]].
func parts_of(i: int) -> Array:
	var out: Array = []
	for mesh_kind: String in _parts:
		var parts: Array = _parts[mesh_kind]
		for k in parts.size():
			if int(parts[k][0]) == i:
				out.append([mesh_kind, k])
	return out
