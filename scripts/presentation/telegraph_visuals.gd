class_name TelegraphVisuals
extends Node3D
## Decision 25's readability layer in the world (plan §3.9). Every Events.telegraph_started gets
## a decal on the ground at the actor - a flat disc (circle), a strip along its facing (line) or
## a fan (cone) - that fills from 0 to 100 % over the windup and flashes while the strike is
## active. Line telegraphs of projectile actions are aim lines instead: a thin beam from the
## launch point (the bow, the staff) to actor.current_aim_point(), which follows the target until
## the aim lock and then freezes (decision 24). Ground decals follow the actor during the windup
## and stay where the strike began. A decal goes as soon as its actor leaves the WINDUP or ACTIVE
## phase of that action instance (interrupted, dead, or the strike is over).
##
## Presentation only: it listens to Events and reads controller state, never changes gameplay.
## main.gd adds one beside HitFeedback. The record helpers (make_record, is_live, progress,
## is_striking, origin_of) are static, so the HUD's threat arrows (ui/hud/threat_arrows.gd) follow
## exactly the same telegraphs. Read API for tests: telegraph_for(actor_id), active_count().

const GROUP := "telegraph_visuals"
const GROUND_LIFT_M := 0.07
const DECAL_THICKNESS_M := 0.02
const BEAM_THICKNESS_M := 0.07
const FLASH_HZ := 10.0
const BASE_COLOR := Color(0.85, 0.16, 0.10, 0.26)
const FILL_COLOR := Color(1.0, 0.40, 0.16, 0.55)
const FLASH_COLOR := Color(1.0, 0.92, 0.55, 0.85)
const BEAM_BASE_COLOR := Color(1.0, 0.32, 0.18, 0.30)
const BEAM_FILL_COLOR := Color(1.0, 0.66, 0.30, 0.85)

var _records: Dictionary = {}   ## actor id -> telegraph record (an actor runs one action at a time)
var _views: Dictionary = {}     ## actor id -> {"base": MeshInstance3D, "fill": MeshInstance3D}
var _spare: Array = []          ## unused views
var _time := 0.0
var _disc: CylinderMesh
var _box: BoxMesh
var _fans: Dictionary = {}      ## rounded arc degrees -> ArrayMesh (unit radius)
var _materials: Dictionary = {} ## "base" | "fill" | "flash" | "beam_base" | "beam_fill" -> material


func _init() -> void:
	name = "TelegraphVisuals"
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	add_to_group(GROUP)
	_disc = CylinderMesh.new()
	_disc.top_radius = 1.0
	_disc.bottom_radius = 1.0
	_disc.height = DECAL_THICKNESS_M
	_disc.radial_segments = 32
	_disc.rings = 1
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	for key: String in ["base", "fill", "flash", "beam_base", "beam_fill"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = {"base": BASE_COLOR, "fill": FILL_COLOR, "flash": FLASH_COLOR,
			"beam_base": BEAM_BASE_COLOR, "beam_fill": BEAM_FILL_COLOR}[key]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	Events.telegraph_started.connect(_on_telegraph_started)


# --------------------------------------------------------------------------- records (static)

## A telegraph record from a telegraph_started event: the event's fields plus the actor's
## current action instance (the event is emitted as the windup begins), the cone's arc and
## whether it is an aim line (a line telegraph on a projectile action).
static func make_record(actor_id: String, action_id: String, target_id: String, shape: String,
		origin: Vector3, yaw: float, radius: float, length: float, duration_s: float) -> Dictionary:
	var e := Sim.get_entity(actor_id)
	var instance := e.controller.instance_id if e != null and e.controller != null else -1
	var a := GameData.get_action(action_id)
	var arc := 90.0
	var aim_line := false
	if a != null:
		var t: Variant = a.param("telegraph")
		if typeof(t) == TYPE_DICTIONARY:
			arc = float(t.get("arc_deg", arc))
		aim_line = shape == "line" and a.hit_shape == "projectile"
	return {"actor_id": actor_id, "action_id": action_id, "target_id": target_id, "shape": shape,
		"origin": origin, "yaw": yaw, "radius": radius, "length": length, "duration_s": duration_s,
		"instance": instance, "arc_deg": arc, "aim_line": aim_line,
		"at": origin, "at_yaw": yaw}


## The controller of a record's actor, or null when the actor is gone.
static func controller_of(rec: Dictionary) -> CombatController:
	var e := Sim.get_entity(str(rec.get("actor_id", "")))
	if e == null or not is_instance_valid(e.actor):
		return null
	return e.controller


## True while the record's actor still runs that action instance in its WINDUP or ACTIVE phase.
static func is_live(rec: Dictionary) -> bool:
	var c := controller_of(rec)
	if c == null or c.action == null or c.instance_id != int(rec.get("instance", -1)) \
			or c.action.id != str(rec.get("action_id", "")):
		return false
	var p := c.phase()
	return p == ActionDef.Phase.WINDUP or p == ActionDef.Phase.ACTIVE


## How full the decal is: 0 -> 1 over the windup (ticks elapsed / windup ticks), 1 once active.
static func progress(rec: Dictionary) -> float:
	var c := controller_of(rec)
	if c == null or c.action == null:
		return 0.0
	if c.phase() == ActionDef.Phase.WINDUP:
		return clampf(float(c.elapsed) / maxf(1.0, float(c.action.windup_ticks)), 0.0, 1.0)
	return 1.0


## True while the telegraphed strike is active (the decal flashes).
static func is_striking(rec: Dictionary) -> bool:
	var c := controller_of(rec)
	return c != null and c.action != null and is_live(rec) and c.phase() == ActionDef.Phase.ACTIVE


## Where the threat comes from now: the actor's attack origin (its feet + 1 m without one), else
## the event's origin.
static func origin_of(rec: Dictionary) -> Vector3:
	var e := Sim.get_entity(str(rec.get("actor_id", "")))
	if e == null or not is_instance_valid(e.actor):
		return rec.get("origin", Vector3.ZERO)
	if e.actor.has_method("attack_origin_global"):
		return e.actor.call("attack_origin_global")
	return e.actor.global_position + Vector3.UP


# --------------------------------------------------------------------------- read API

## How many telegraphs are showing (live ones only).
func active_count() -> int:
	var n := 0
	for rec: Dictionary in _records.values():
		if is_live(rec):
			n += 1
	return n


## The live telegraph of `actor_id` now ({} when it has none): {"action_id", "target_id", "shape",
## "fill" (0..1), "striking", "aim_line", "start" / "end" (the aim line's ends; for ground decals
## the strip's or the fan's origin and the point its length reaches), "visible" (its decal is
## drawn)}.
func telegraph_for(actor_id: String) -> Dictionary:
	var rec: Dictionary = _records.get(actor_id, {})
	if rec.is_empty() or not is_live(rec):
		return {}
	var ends := _ends(rec)
	var view: Dictionary = _views.get(actor_id, {})
	var shown: bool = not view.is_empty() and (view.base as MeshInstance3D).visible
	return {"action_id": rec.action_id, "target_id": rec.target_id, "shape": rec.shape,
		"fill": progress(rec), "striking": is_striking(rec), "aim_line": rec.aim_line,
		"start": ends[0], "end": ends[1], "visible": shown}


# --------------------------------------------------------------------------- events and drawing

func _on_telegraph_started(_tick: int, actor_id: String, action_id: String, target_id: String,
		shape: String, origin: Vector3, yaw: float, radius: float, length: float, duration_s: float) -> void:
	_records[actor_id] = make_record(actor_id, action_id, target_id, shape, origin, yaw, radius, length,
		duration_s)


func _process(delta: float) -> void:
	_time += delta
	for actor_id: String in _records.keys():
		var rec: Dictionary = _records[actor_id]
		if not is_live(rec):
			_records.erase(actor_id)
			_release_view(actor_id)
			continue
		_draw_record(actor_id, rec)


## [start, end] of a record now: an aim line from the launch point to the aim point; a ground
## decal from where it stands along its facing (radius for circles and cones, length for lines).
func _ends(rec: Dictionary) -> Array:
	var e := Sim.get_entity(str(rec.actor_id))
	var actor: Node3D = e.actor if e != null and is_instance_valid(e.actor) else null
	if bool(rec.aim_line) and actor != null:
		var a := GameData.get_action(str(rec.action_id))
		var start: Vector3 = actor.call("launch_point_global", a) if actor.has_method("launch_point_global") \
			else actor.global_position + Vector3.UP * 1.4
		var end: Vector3 = actor.call("current_aim_point") if actor.has_method("current_aim_point") else Vector3.INF
		if end == Vector3.INF:
			end = start + _forward(actor.global_rotation.y) * float(rec.length)
		return [start, end]
	if actor != null and not is_striking(rec) and not _p30_band(rec, actor):
		# Ground decals follow the actor through the windup; the strike stays where it began.
		rec["at"] = actor.global_position
		rec["at_yaw"] = actor.global_rotation.y
	var at: Vector3 = rec.at
	var reach := float(rec.length) if str(rec.shape) == "line" else float(rec.radius)
	return [at, at + _forward(float(rec.at_yaw)) * reach]


static func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _draw_record(actor_id: String, rec: Dictionary) -> void:
	var view := _view_for(actor_id)
	var base: MeshInstance3D = view.base
	var fill_mi: MeshInstance3D = view.fill
	var fill := progress(rec)
	var flash := is_striking(rec) and fmod(_time * FLASH_HZ, 1.0) < 0.5
	var ends := _ends(rec)
	var start: Vector3 = ends[0]
	var end: Vector3 = ends[1]
	base.visible = true
	fill_mi.visible = fill > 0.0
	if bool(rec.aim_line):
		var seg := end - start
		var length := seg.length()
		if length < 0.01:
			base.visible = false
			fill_mi.visible = false
			return
		var dir := seg / length
		var look := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		base.mesh = _box
		base.material_override = _materials.beam_base
		base.global_transform = Transform3D(look * Basis.from_scale(Vector3(BEAM_THICKNESS_M,
			BEAM_THICKNESS_M, length)), start + seg * 0.5)
		fill_mi.mesh = _box
		fill_mi.material_override = _materials.flash if flash else _materials.beam_fill
		var filled := maxf(length * fill, 0.01)
		fill_mi.global_transform = Transform3D(look * Basis.from_scale(Vector3(BEAM_THICKNESS_M * 1.6,
			BEAM_THICKNESS_M * 1.6, filled)), start + dir * (filled * 0.5))
		return
	var yaw := float(rec.at_yaw)
	var at: Vector3 = start + Vector3.UP * GROUND_LIFT_M
	var turn := Basis(Vector3.UP, yaw)
	base.material_override = _materials.base
	fill_mi.material_override = _materials.flash if flash else _materials.fill
	match str(rec.shape):
		"circle":
			var r := maxf(float(rec.radius), 0.1)
			base.mesh = _disc
			base.global_transform = Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), at)
			fill_mi.mesh = _disc
			var fr := maxf(r * fill, 0.01)
			fill_mi.global_transform = Transform3D(Basis.from_scale(Vector3(fr, 1.2, fr)), at + Vector3.UP * 0.005)
		"cone":
			var r := maxf(float(rec.radius), 0.1)
			var fan := _fan_mesh(float(rec.arc_deg))
			base.mesh = fan
			base.global_transform = Transform3D(turn * Basis.from_scale(Vector3(r, 1.0, r)), at)
			fill_mi.mesh = fan
			var fr := maxf(r * fill, 0.01)
			fill_mi.global_transform = Transform3D(turn * Basis.from_scale(Vector3(fr, 1.0, fr)), at + Vector3.UP * 0.005)
		_:
			var length := maxf(float(rec.length), 0.1)
			var width := maxf(float(rec.radius) * 2.0, 0.1)
			var fwd := _forward(yaw)
			base.mesh = _box
			base.global_transform = Transform3D(turn * Basis.from_scale(Vector3(width, DECAL_THICKNESS_M, length)),
				at + fwd * (length * 0.5))
			fill_mi.mesh = _box
			var filled := maxf(length * fill, 0.01)
			fill_mi.global_transform = Transform3D(turn * Basis.from_scale(Vector3(width * 0.8,
				DECAL_THICKNESS_M * 1.5, filled)), at + fwd * (filled * 0.5) + Vector3.UP * 0.005)


func _view_for(actor_id: String) -> Dictionary:
	if _views.has(actor_id):
		return _views[actor_id]
	var view: Dictionary = _spare.pop_back() if not _spare.is_empty() else _make_view()
	_views[actor_id] = view
	return view


func _make_view() -> Dictionary:
	var view := {}
	for key: String in ["base", "fill"]:
		var mi := MeshInstance3D.new()
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		view[key] = mi
	return view


func _release_view(actor_id: String) -> void:
	var view: Dictionary = _views.get(actor_id, {})
	_views.erase(actor_id)
	if view.is_empty():
		return
	for key: String in ["base", "fill"]:
		(view[key] as MeshInstance3D).visible = false
	_spare.append(view)


## A flat fan of `arc_deg` around local -Z with radius 1 (scaled by the cone's radius).
func _fan_mesh(arc_deg: float) -> ArrayMesh:
	var key := int(roundf(arc_deg))
	if _fans.has(key):
		return _fans[key]
	var segments := maxi(6, int(arc_deg / 6.0))
	var half := deg_to_rad(arc_deg * 0.5)
	var verts := PackedVector3Array()
	for i in segments:
		var a0 := lerpf(-half, half, float(i) / segments)
		var a1 := lerpf(-half, half, float(i + 1) / segments)
		verts.append(Vector3.ZERO)
		verts.append(Vector3(-sin(a0), 0.0, -cos(a0)))
		verts.append(Vector3(-sin(a1), 0.0, -cos(a1)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_fans[key] = mesh
	return mesh


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P30
# A formation's brace (P30, plan M6-M9 §2.10): its band telegraph is a line telegraph along the
# formation's front rank - the event's origin is the front rank's centre, its radius half the rank's
# width, its length the band's depth - announced once through the striker (EnemyActor). It stays
# where the band lies instead of following the striker (the hook in _ends).

## True when `rec` is a band telegraph (its action's hit shape is band_pulse): it keeps its origin.
static func _p30_band(rec: Dictionary, _actor: Node3D) -> bool:
	var a := GameData.get_action(str(rec.get("action_id", "")))
	return a != null and a.hit_shape == "band_pulse"

## @anchor P31

## @anchor P32

## @anchor P34
