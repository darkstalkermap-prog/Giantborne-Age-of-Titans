extends HudWidget
## C3 (decision C3-4): the aim indicator - what the next light swing will strike, drawn where it stands. The
## crosshair at the screen's centre is the cursor; the swing plan (PlayerAttack.next_swing_plan: the lock, else
## what is under the cursor, else the soft target in front) sweeps the arc as the runner will, and this draws:
##   * corner brackets round what the swing will strike (its body on the screen, or the plate of a titan it will
##     land on, with a dot at that plate), warm when it is struck, and its name - a titan's with the plate's
##     ("Stoneback - left shoulder");
##   * an aimed target the swing does not reach: grey brackets and "Out of reach - 3 m closer";
##   * the swing's reach: a dotted arc on the ground at the arm's and the weapon's length across the arc's width,
##     while something is aimed at.
## Hidden while the giant holds a lock (the lock marker and its target frame show it), in first person over a
## menu, and when nothing is aimed. Full-rect overlay of rectangles (HudKit's batch) and two labels; recomputed
## every RECOMPUTE_FRAMES frames. Read API: indicated() -> {"entity_id", "region", "reaches", "source", "aimed_id"}.

const RECOMPUTE_FRAMES := 2
const WARM := Color(1.0, 0.62, 0.22)
const COLD := Color(0.72, 0.74, 0.78, 0.8)
const SHADE := Color(0, 0, 0, 0.5)
const REACH_DOTS := 11
const BRACKET_PX := 10.0
const MIN_BOX_PX := 18.0

var _plan: Dictionary = {}
var _frame := 0
var _label: Label
var _sub: Label
var _box := Rect2()
var _dot := Vector2.INF
var _reach: PackedVector2Array = PackedVector2Array()
var _warm := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudKit.set_z(self, HudKit.Z_OVERLAY)
	_label = HudKit.label("", HudKit.TEXT, WARM, HudKit.Z_OVERLAY_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(260, 18)
	_label.visible = false
	add_child(_label)
	_sub = HudKit.label("", HudKit.SMALL, COLD, HudKit.Z_OVERLAY_TEXT)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size = Vector2(260, 16)
	_sub.visible = false
	add_child(_sub)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame % RECOMPUTE_FRAMES == 0 or _plan.is_empty():
		_plan = _compute_plan()
	_layout()
	queue_redraw()


func _compute_plan() -> Dictionary:
	var p := player()
	if p == null or p.attack == null or p.camera_rig == null or p.camera_rig.camera == null \
			or not p.camera_rig.camera.is_inside_tree() or not p.is_inside_tree():
		return {}
	if p.targeting != null and p.targeting.locked_entity() != null:
		return {}
	if p.controller == null or p.controller.state == CombatController.State.DEAD:
		return {}
	return p.attack.next_swing_plan()


## What the indicator shows now: {"entity_id" (what the swing will strike; "" for nothing), "region", "reaches",
## "source", "aimed_id" (what it aims at, struck or not)}.
func indicated() -> Dictionary:
	if _plan.is_empty():
		return {"entity_id": "", "region": "", "reaches": false, "source": "none", "aimed_id": ""}
	var prim_v: Variant = _plan.get("primary")
	var aimed_v: Variant = _plan.get("entity")
	return {"entity_id": (prim_v as CombatEntity).entity_id if is_instance_valid(prim_v) else "",
		"region": str(_plan.get("primary_region", "")), "reaches": bool(_plan.get("reaches", false)),
		"source": str(_plan.get("source", "none")),
		"aimed_id": (aimed_v as CombatEntity).entity_id if is_instance_valid(aimed_v) else ""}


## Recomputes now (tests; the widget recomputes every RECOMPUTE_FRAMES frames on its own).
func refresh_now() -> Dictionary:
	_plan = _compute_plan()
	_layout()
	return indicated()


func _layout() -> void:
	_box = Rect2()
	_dot = Vector2.INF
	_reach = PackedVector2Array()
	_label.visible = false
	_sub.visible = false
	var p := player()
	if _plan.is_empty() or p == null:
		return
	var cam := p.camera_rig.camera
	var prim_v: Variant = _plan.get("primary")
	var aimed_v: Variant = _plan.get("entity")
	var prim: CombatEntity = prim_v as CombatEntity if is_instance_valid(prim_v) else null
	var aimed: CombatEntity = aimed_v as CombatEntity if is_instance_valid(aimed_v) else null
	var show: CombatEntity = prim if prim != null else aimed
	if show == null or show.actor == null or not is_instance_valid(show.actor):
		return
	_warm = prim != null
	var region := str(_plan.get("primary_region", "")) if _warm else str(_plan.get("region", ""))
	var hb := PlayerAttack._nearest_hurtbox(show, show.anchor_position()) if show.plates == null else _region_box(show, region)
	if show.plates != null and hb != null:
		var c := hb.global_position
		var r := _hurtbox_extent(hb)
		_box = _screen_box(cam, [c + Vector3(-r, -r, 0), c + Vector3(r, r, 0), c + Vector3(0, 0, -r), c + Vector3(0, 0, r)])
		if not cam.is_position_behind(c):
			_dot = cam.unproject_position(c)
	else:
		var base := (show.actor as Node3D).global_position
		var h := show.combatant.height_m
		var rad := EnemyActor.entity_radius(show)
		var right := cam.global_transform.basis.x
		_box = _screen_box(cam, [base - right * rad, base + right * rad, base + Vector3.UP * h - right * rad,
			base + Vector3.UP * h + right * rad])
	if _box.size == Vector2.ZERO:
		return
	_box = _box.grow(4.0)
	if _box.size.x < MIN_BOX_PX:
		_box = _box.grow_individual((MIN_BOX_PX - _box.size.x) * 0.5, 0, (MIN_BOX_PX - _box.size.x) * 0.5, 0)
	if _box.size.y < MIN_BOX_PX:
		_box = _box.grow_individual(0, (MIN_BOX_PX - _box.size.y) * 0.5, 0, (MIN_BOX_PX - _box.size.y) * 0.5)
	var name := show.display_name()
	if show.plates != null and region != "":
		name += " - " + region_label(region)
	_label.text = name
	_label.add_theme_color_override("font_color", WARM if _warm else COLD)
	_label.position = Vector2(_box.get_center().x - 130.0, _box.position.y - 22.0)
	_label.visible = true
	if not _warm:
		var short := float(_plan.get("short_m", 0.0))
		_sub.text = "Out of reach" + (" - %d m closer" % ceili(short) if short >= 0.5
			else (" - too close" if bool(_plan.get("too_close", false)) else ""))
		_sub.position = Vector2(_box.get_center().x - 130.0, _box.end.y + 4.0)
		_sub.visible = true
	_reach = _reach_dots(p, cam)


static func _hurtbox_extent(hb: Hurtbox) -> float:
	for c in hb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var s: Shape3D = (c as CollisionShape3D).shape
			if s is SphereShape3D:
				return (s as SphereShape3D).radius
			if s is BoxShape3D:
				return (s as BoxShape3D).size.length() * 0.35
			if s is CapsuleShape3D:
				return (s as CapsuleShape3D).height * 0.4
	return 1.0


static func _region_box(e: CombatEntity, region: String) -> Hurtbox:
	for hb: Hurtbox in PlayerAttack._hurtboxes_of(e):
		if hb.region == region:
			return hb
	return PlayerAttack._nearest_hurtbox(e, e.anchor_position())


static func _screen_box(cam: Camera3D, points: Array) -> Rect2:
	var r := Rect2()
	var any := false
	for pt: Vector3 in points:
		if cam.is_position_behind(pt):
			continue
		var s := cam.unproject_position(pt)
		if not any:
			r = Rect2(s, Vector2.ZERO)
			any = true
		else:
			r = r.expand(s)
	return r if any else Rect2()


## The swing's reach on the ground: REACH_DOTS points at the arm's and the weapon's length across the arc's yaw.
func _reach_dots(p: GiantPlayer, cam: Camera3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var def: ActionDef = p.controller.library.get(p.controller.next_light_id()) if p.controller.next_light_id() != "" else null
	if def == null or def.arc.is_empty():
		return out
	var reach := p.attack.reach_estimate(def)
	var y0 := deg_to_rad(float(def.arc.get("yaw_start_deg", 60.0)))
	var y1 := deg_to_rad(float(def.arc.get("yaw_end_deg", -60.0)))
	var basis := Basis(Vector3.UP, float(_plan.get("yaw", p.facing_yaw)))
	for i in REACH_DOTS:
		var a := lerpf(y0, y1, float(i) / float(REACH_DOTS - 1))
		var local := Vector3(sin(a), 0.0, -cos(a)) * reach
		var w := p.global_position + basis * local + Vector3.UP * 0.1
		if not cam.is_position_behind(w):
			out.append(cam.unproject_position(w))
	return out


## "shoulder_l" -> "left shoulder", "greave_r" -> "right greave", "back" -> "back".
static func region_label(region: String) -> String:
	var parts := region.split("_", false)
	var side := ""
	if parts.size() > 1 and parts[parts.size() - 1] in ["l", "r"]:
		side = "left " if parts[parts.size() - 1] == "l" else "right "
		parts.remove_at(parts.size() - 1)
	return side + " ".join(parts)


func _draw() -> void:
	if _box.size == Vector2.ZERO:
		return
	var col := WARM if _warm else COLD
	for pt: Vector2 in _reach:
		draw_rect(Rect2(pt - Vector2(2, 2), Vector2(4, 4)), SHADE)
		draw_rect(Rect2(pt - Vector2(1, 1), Vector2(2, 2)), Color(col, 0.75))
	var b := _box
	var k := minf(BRACKET_PX, minf(b.size.x, b.size.y) * 0.4)
	for corner: Vector2 in [b.position, Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y), b.end]:
		var sx := 1.0 if corner.x <= b.get_center().x else -1.0
		var sy := 1.0 if corner.y <= b.get_center().y else -1.0
		var hr := Rect2(Vector2(minf(corner.x, corner.x + sx * k), corner.y - 1.0), Vector2(k, 2.5))
		var vr := Rect2(Vector2(corner.x - 1.0, minf(corner.y, corner.y + sy * k)), Vector2(2.5, k))
		draw_rect(hr.grow(1.0), SHADE)
		draw_rect(vr.grow(1.0), SHADE)
		draw_rect(hr, col)
		draw_rect(vr, col)
	if _dot.is_finite():
		HudKit.draw_dot(self, _dot, 4.0, SHADE)
		HudKit.draw_dot(self, _dot, 2.5, col)
