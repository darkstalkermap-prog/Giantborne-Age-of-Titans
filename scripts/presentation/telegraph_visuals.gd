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
	_p32_ready()   # P32: an indirect shot's landing circle stays through the flight


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
		if not is_live(rec) and not _p32_in_flight(rec):
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
	if actor != null and not is_striking(rec) and not _p30_band(rec, actor) and not _p31_at_target(rec) \
			and not _p32_landing(rec):
		# Ground decals follow the actor through the windup; the strike stays where it began.
		rec["at"] = actor.global_position
		rec["at_yaw"] = actor.global_rotation.y
	var at: Vector3 = rec.at
	var reach := float(rec.length) if str(rec.shape) == "line" else float(rec.radius)
	return [at, at + _forward(float(rec.at_yaw)) * reach]


static func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _draw_record(actor_id: String, rec: Dictionary) -> void:
	if _p32_draw_flight(actor_id, rec):
		return   # P32: the landing circle while the shot flies
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
	_p31_restyle(rec, base, fill_mi, flash)   # P31: the giant's own telegraphs (a crack, its colours)


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
# The giant's own telegraphs (P31, plan M6-M9 §5.12): PlayerAttack announces an ability's telegraph
# like an enemy's - Earthquake's line along its facing, Storm Call's circle on the lock target. They
# are drawn in the giant's colours (never the threat red), a line as a jagged ground crack; a
# telegraph whose action says `at: "target"` follows its target through the windup (the hook in
# _ends) and stays where the strike falls.

const P31_BASE_COLOR := Color(0.95, 0.70, 0.28, 0.22)
const P31_FILL_COLOR := Color(1.0, 0.80, 0.40, 0.55)
const P31_FLASH_COLOR := Color(1.0, 0.97, 0.80, 0.85)
const P31_CRACK_SEGMENTS := 14

var _p31_crack: ArrayMesh


## True when `rec`'s action is telegraphed at its target (telegraph.at "target"): until the strike
## begins the decal stands on the target (it keeps its last place once the target is gone).
func _p31_at_target(rec: Dictionary) -> bool:
	var a := GameData.get_action(str(rec.get("action_id", "")))
	var t: Variant = a.param("telegraph") if a != null else null
	if typeof(t) != TYPE_DICTIONARY or str((t as Dictionary).get("at", "actor")) != "target":
		return false
	var target := Sim.get_entity(str(rec.get("target_id", "")))
	if target != null and is_instance_valid(target.actor) and target.is_alive():
		rec["at"] = (target.actor as Node3D).global_position
	return true


## True when the record is the giant's own telegraph.
static func p31_is_players(rec: Dictionary) -> bool:
	var e := Sim.get_entity(str(rec.get("actor_id", "")))
	return e != null and is_instance_valid(e.actor) and e.actor is GiantPlayer


## The giant's own ground telegraphs: its colours, and a crack instead of a strip for a line.
func _p31_restyle(rec: Dictionary, base: MeshInstance3D, fill_mi: MeshInstance3D, flash: bool) -> void:
	if bool(rec.aim_line) or not p31_is_players(rec):
		return
	base.material_override = _p31_material("p31_base", P31_BASE_COLOR)
	fill_mi.material_override = _p31_material("p31_flash", P31_FLASH_COLOR) if flash \
		else _p31_material("p31_fill", P31_FILL_COLOR)
	if not (str(rec.shape) in ["circle", "cone"]):
		base.mesh = _p31_crack_mesh()
		fill_mi.mesh = base.mesh


func _p31_material(key: String, color: Color) -> Material:
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


## A flat jagged crack one unit long (local z -0.5 .. 0.5) and one unit wide at most, with a short
## branch every few segments (scaled like the strip it replaces).
func _p31_crack_mesh() -> ArrayMesh:
	if _p31_crack != null:
		return _p31_crack
	var verts := PackedVector3Array()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in P31_CRACK_SEGMENTS + 1:
		var f := float(i) / P31_CRACK_SEGMENTS
		var z := 0.5 - f
		var x := 0.22 * sin(f * 23.0) * (0.4 + 0.6 * f)
		var half := 0.10 + 0.22 * absf(sin(f * 9.0 + 0.7))
		var l := Vector3(x - half, 0.0, z)
		var r := Vector3(x + half, 0.0, z)
		if i > 0:
			verts.append_array(PackedVector3Array([prev_l, prev_r, r, prev_l, r, l]))
			if i % 3 == 0:
				var side := 1.0 if i % 2 == 0 else -1.0
				var root := Vector3(x, 0.0, z)
				verts.append_array(PackedVector3Array([root + Vector3(0.0, 0.0, 0.03), root - Vector3(0.0, 0.0, 0.03),
					root + Vector3(side * 0.48, 0.0, -0.05)]))
		prev_l = l
		prev_r = r
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	_p31_crack = ArrayMesh.new()
	_p31_crack.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _p31_crack


## @anchor P32
# An indirect shot's landing circle (P32, plan M6-M9 §2.10, §3.16: the catapult): the telegraph of an
# action CueRouter.is_indirect calls indirect (its stone) lies at its landing point - the event's
# origin - and stays there instead of following the engine (the hook in _ends). It fills over the
# windup as every telegraph does, and when the shot is launched (Events.projectile_spawned by the same
# actor and action) it stays on through the flight with its timer: the fill grows again from the
# middle to the rim as the stone comes down (the flight time from the launch's horizontal speed,
# CueRouter.flight_seconds) and flashes for the last P32_FLASH_S. It goes when the stone lands
# (Events.projectile_impact), or at the latest P32_GRACE_S after the expected landing. The audio's
# rising incoming whistle sounds over the same circle (P28).

const P32_FLASH_S := 0.35
const P32_GRACE_S := 1.0


func _p32_ready() -> void:
	if not Events.projectile_spawned.is_connected(_p32_on_projectile_spawned):
		Events.projectile_spawned.connect(_p32_on_projectile_spawned)
	if not Events.projectile_impact.is_connected(_p32_on_projectile_impact):
		Events.projectile_impact.connect(_p32_on_projectile_impact)


## True when `rec` is an indirect shot's landing circle (it keeps its origin).
static func _p32_landing(rec: Dictionary) -> bool:
	if rec.has("p32_landing"):
		return bool(rec.p32_landing)
	var a := GameData.get_action(str(rec.get("action_id", "")))
	var landing := a != null and str(rec.get("shape", "")) == "circle" and CueRouter.is_indirect(a)
	rec["p32_landing"] = landing
	return landing


## True while `rec`'s shot is in the air (launched, not yet landed, not past its expected landing by
## more than P32_GRACE_S).
func _p32_in_flight(rec: Dictionary) -> bool:
	if not rec.has("p32_projectile"):
		return false
	return _time - float(rec.p32_launch_s) <= float(rec.p32_flight_s) + P32_GRACE_S


## The landing circle's state for tests: {} when `actor_id` has no shot in the air; else {"projectile",
## "point", "radius", "timer" (0..1 of the flight), "flight_s"}.
func landing_for(actor_id: String) -> Dictionary:
	var rec: Dictionary = _records.get(actor_id, {})
	if rec.is_empty() or not _p32_in_flight(rec):
		return {}
	return {"projectile": int(rec.p32_projectile), "point": rec.origin, "radius": float(rec.radius),
		"timer": _p32_timer(rec), "flight_s": float(rec.p32_flight_s)}


func _p32_timer(rec: Dictionary) -> float:
	return clampf((_time - float(rec.p32_launch_s)) / maxf(0.05, float(rec.p32_flight_s)), 0.0, 1.0)


func _p32_on_projectile_spawned(_tick: int, projectile_id: int, owner_id: String, action_id: String,
		position: Vector3, velocity: Vector3, _visual: String) -> void:
	var rec: Dictionary = _records.get(owner_id, {})
	if rec.is_empty() or str(rec.get("action_id", "")) != action_id or not _p32_landing(rec):
		return
	var a := GameData.get_action(action_id)
	var gravity := float(Projectile.spec_for(a).gravity_mps2) if a != null else 0.0
	rec["p32_projectile"] = projectile_id
	rec["p32_launch_s"] = _time
	rec["p32_flight_s"] = CueRouter.flight_seconds(position, velocity, rec.origin, gravity)


func _p32_on_projectile_impact(_tick: int, projectile_id: int, _point: Vector3, _hit_id: String) -> void:
	for actor_id: String in _records.keys():
		var rec: Dictionary = _records[actor_id]
		if int(rec.get("p32_projectile", -1)) == projectile_id:
			_records.erase(actor_id)
			_release_view(actor_id)
			return


## Draws the landing circle of a shot in flight (true when it did): the base disc and a fill growing
## with the flight timer, flashing as it ends.
func _p32_draw_flight(actor_id: String, rec: Dictionary) -> bool:
	if is_live(rec) or not _p32_in_flight(rec):
		return false
	var view := _view_for(actor_id)
	var base: MeshInstance3D = view.base
	var fill_mi: MeshInstance3D = view.fill
	var r := maxf(float(rec.radius), 0.1)
	var at: Vector3 = (rec.origin as Vector3) + Vector3.UP * GROUND_LIFT_M
	var timer := _p32_timer(rec)
	var left := float(rec.p32_flight_s) * (1.0 - timer)
	var flash := left <= P32_FLASH_S and fmod(_time * FLASH_HZ, 1.0) < 0.5
	base.visible = true
	base.mesh = _disc
	base.material_override = _materials.base
	base.global_transform = Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), at)
	fill_mi.visible = true
	fill_mi.mesh = _disc
	fill_mi.material_override = _materials.flash if flash else _materials.fill
	var fr := maxf(r * timer, 0.01)
	fill_mi.global_transform = Transform3D(Basis.from_scale(Vector3(fr, 1.2, fr)), at + Vector3.UP * 0.005)
	return true

## @anchor P34
