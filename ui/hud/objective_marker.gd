extends HudWidget
## The objective marker (plan §2.10.1, §3.15 design 6; P13): a diamond projected at the current
## objective's position (Quests.current_objective(): its marker, else its first target found),
## with the horizontal distance under it ("86 m"). A point off screen or behind the camera is
## clamped to a rectangle INSET_PX inside the screen edge, in its direction (behind the camera
## and straight ahead/behind: the bottom edge). Hidden while quests are inactive, without an
## objective position, or within HIDE_WITHIN_M. Full-rect overlay that draws only the marker.
## M4 gate: drawn over every panel (the last widgets but the threat arrows), and a clamped marker
## that would sit on a fixed panel drawn now (the tutorial prompt, the hotbar, the tracker, ...;
## Hud.overlay_keep_out) slides along the edge until the diamond, its arrow and its distance clear
## it (HudEdge.clear_of): still INSET_PX inside the edge, still pointing at the objective.
## Read API: placement_now(), visible_text(); the geometry is static (placement, edge_point).
## P27: it follows the tracked quest (Quests.current_objective(): the tracked quest's objective; for
## a multi-marker stage the marker nearest the giant, while the compass shows them all), and it is
## drawn by HudKit's rules: the diamond, its outline and the off-screen arrow are turned rectangles
## on the edge-overlay layer (HudKit.Z_OVERLAY, over every panel and its text), the distance a
## shadowed label on the layer above.

const INSET_PX := 36.0
const HALF_SIZE_PX := 11.0
const HIDE_WITHIN_M := 3.0
const COLOR := Color(1.0, 0.82, 0.30)
## What the marker covers around its point: the diamond (and outline), the off-screen arrow in any
## direction (to HALF_SIZE_PX + 9 px) and the 80 x 18 px distance label under the diamond.
const FOOTPRINT := Rect2(-40.0, -22.0, 80.0, 53.0)

var _place: Dictionary = {}
var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudKit.set_z(self, HudKit.Z_OVERLAY)
	_label = HudKit.label("", HudKit.TEXT, COLOR, HudKit.Z_OVERLAY_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(80, 18)
	_label.visible = false
	add_child(_label)


func _process(_delta: float) -> void:
	_place = _compute()
	if _place.is_empty():
		_label.visible = false
	else:
		_label.visible = true
		_label.text = distance_text(float(_place.distance))
		_label.position = (_place.position as Vector2) + Vector2(-40.0, HALF_SIZE_PX + 2.0)
	queue_redraw()


func _compute() -> Dictionary:
	if not Quests.is_active():
		return {}
	var p := player()
	if p == null or p.camera_rig == null or p.camera_rig.camera == null or not p.camera_rig.camera.is_inside_tree():
		return {}
	var pos: Variant = Quests.current_objective().get("position", Vector3.INF)
	if typeof(pos) != TYPE_VECTOR3 or not (pos as Vector3).is_finite():
		return {}
	var flat := (pos as Vector3) - p.global_position
	flat.y = 0.0
	if flat.length() < HIDE_WITHIN_M:
		return {}
	var view := get_viewport_rect().size
	var out := placement(p.camera_rig.camera, pos, view, INSET_PX)
	if not bool(out.on_screen) and hud != null and is_instance_valid(hud):
		out.position = HudEdge.clear_of(out.position, view, INSET_PX, FOOTPRINT, hud.overlay_keep_out(view))
	out["distance"] = flat.length()
	out["target"] = pos
	return out


## Where the marker for `point` goes on a `view`-sized screen seen by `cam`: {"position" (px),
## "on_screen" (inside the inset rectangle), "direction" (unit, x right / y down; zero when on
## screen)}. Off screen or behind the camera it sits on the rectangle INSET px inside the edge,
## slid along it clear of the `keep_out` rects (the HUD's panels drawn now; none: the plain edge
## point).
static func placement(cam: Camera3D, point: Vector3, view: Vector2, inset: float, keep_out: Array = []) -> Dictionary:
	var rect := Rect2(Vector2(inset, inset), view - Vector2(inset, inset) * 2.0)
	if not cam.is_position_behind(point):
		var sp := cam.unproject_position(point)
		if rect.has_point(sp):
			return {"position": sp, "on_screen": true, "direction": Vector2.ZERO}
		var d := sp - view * 0.5
		var dir := d.normalized() if d.length_squared() > 1e-6 else Vector2(0.0, 1.0)
		return {"position": HudEdge.clear_of(edge_point(view, dir, inset), view, inset, FOOTPRINT, keep_out),
			"on_screen": false, "direction": dir}
	var local := cam.global_transform.affine_inverse() * point
	var back := Vector2(local.x, -local.y)
	var bdir := back.normalized() if back.length_squared() > 1e-8 else Vector2(0.0, 1.0)
	return {"position": HudEdge.clear_of(edge_point(view, bdir, inset), view, inset, FOOTPRINT, keep_out),
		"on_screen": false, "direction": bdir}


## Where a ray from the centre of a `view`-sized screen along `dir` meets the rectangle `inset`
## pixels inside its edge.
static func edge_point(view: Vector2, dir: Vector2, inset: float) -> Vector2:
	return HudEdge.edge_point(view, dir, inset)


## "86 m" (whole metres).
static func distance_text(metres: float) -> String:
	return "%d m" % roundi(metres)


## The marker now: {} while hidden, else placement() plus "distance" and "target".
func placement_now() -> Dictionary:
	return _place


## The distance text shown now ("" while hidden).
func visible_text() -> String:
	return _label.text if _label != null and _label.visible else ""


func _draw() -> void:
	if _place.is_empty():
		return
	var c: Vector2 = _place.position
	var r := HALF_SIZE_PX
	HudKit.draw_diamond(self, c, r, Color(COLOR.r, COLOR.g, COLOR.b, 0.35))
	HudKit.draw_diamond_outline(self, c, r, COLOR, 2.0)
	HudKit.draw_dot(self, c, 2.0, COLOR)
	if not bool(_place.on_screen):
		var dir: Vector2 = _place.direction
		HudKit.draw_pointer(self, c + dir * (r + 9.0), dir, 9.0, 10.0, COLOR)
