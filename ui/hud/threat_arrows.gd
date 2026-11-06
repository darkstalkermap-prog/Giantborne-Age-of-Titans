extends HudWidget
## Screen-edge threat arrows (decision 25, plan §3.9, §2.10.1): for every live telegraph aimed at
## the player (Events.telegraph_started with target_id = the player's entity id) whose origin -
## the attacker - is behind the camera or outside the view, an arrow whose tip sits
## EDGE_INSET_PX inside the screen edge points toward it. It brightens as the windup completes
## (MIN_ALPHA -> 1) and goes with the telegraph (TelegraphVisuals.is_live: the actor left that
## action's WINDUP / ACTIVE). Casts on allies (targets_ally: the barrier) threaten nobody and get
## none. Full-rect overlay that draws nothing else; reads state, never changes it.
## M4 gate: the last HUD widget (it draws over every panel), and a tip that would put the arrow on
## a fixed panel drawn now (the tutorial prompt, the hotbar, the tracker, the boss bar, ...;
## Hud.overlay_keep_out) slides along the edge until the arrow clears it (HudEdge.clear_of): still
## EDGE_INSET_PX inside the edge, still pointing at the threat.
## Read API: arrows() (computed now), visible_count(); geometry: tip_for(), footprint().
## P27: drawn by HudKit's rules - each arrow a dark rhombus with the coloured one inside, turned
## rectangles on the edge-overlay layer (HudKit.Z_OVERLAY: over every panel and its text) - so all
## the arrows on screen are one batch (they were a polygon and a polyline each).

const EDGE_INSET_PX := 24.0
const ARROW_LENGTH_PX := 26.0
const ARROW_WIDTH_PX := 20.0
const MIN_ALPHA := 0.35
const COLOR := Color(1.0, 0.30, 0.16)

var _records: Dictionary = {}   ## attacker id -> telegraph record (TelegraphVisuals.make_record)
var _arrows: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudKit.set_z(self, HudKit.Z_OVERLAY)
	Events.telegraph_started.connect(_on_telegraph_started)


func _on_telegraph_started(_tick: int, actor_id: String, action_id: String, target_id: String,
		shape: String, origin: Vector3, yaw: float, radius: float, length: float, duration_s: float) -> void:
	var p := player()
	if p == null or p.entity == null or target_id != p.entity.entity_id:
		return
	var a := GameData.get_action(action_id)
	if a != null and is_same(a.param("targets_ally", false), true):
		return
	_records[actor_id] = TelegraphVisuals.make_record(actor_id, action_id, target_id, shape, origin, yaw,
		radius, length, duration_s)


func _process(_delta: float) -> void:
	_arrows = arrows()
	queue_redraw()


## The arrows to draw now: [{"actor_id", "action_id", "position" (the tip, px; tip_for), "direction"
## (unit, screen space: x right, y down), "alpha"}] for every live player-aimed telegraph whose
## attacker is off screen or behind the camera.
func arrows() -> Array:
	var out: Array = []
	var p := player()
	var cam: Camera3D = p.camera_rig.camera if p != null and p.camera_rig != null else null
	var view := get_viewport_rect().size
	var keep_out: Array = []
	var have_keep_out := false
	for actor_id: String in _records.keys():
		var rec: Dictionary = _records[actor_id]
		if not TelegraphVisuals.is_live(rec):
			_records.erase(actor_id)
			continue
		if cam == null or not cam.is_inside_tree():
			continue
		var origin := TelegraphVisuals.origin_of(rec)
		if not offscreen(cam, origin, view):
			continue
		if not have_keep_out:
			keep_out = hud.overlay_keep_out(view) if hud != null and is_instance_valid(hud) else []
			have_keep_out = true
		var dir := screen_direction(cam, origin)
		out.append({"actor_id": actor_id, "action_id": rec.action_id,
			"position": tip_for(view, dir, keep_out), "direction": dir,
			"alpha": lerpf(MIN_ALPHA, 1.0, TelegraphVisuals.progress(rec))})
	return out


## How many arrows show now.
func visible_count() -> int:
	return arrows().size()


## True when `point` is behind `cam` or projects outside a view of `view` pixels.
static func offscreen(cam: Camera3D, point: Vector3, view: Vector2) -> bool:
	if cam.is_position_behind(point):
		return true
	return not Rect2(Vector2.ZERO, view).has_point(cam.unproject_position(point))


## The screen direction (x right, y down; unit length) from the view's centre toward `point`, in
## front of the camera or behind it (straight behind or ahead: down).
static func screen_direction(cam: Camera3D, point: Vector3) -> Vector2:
	var local := cam.global_transform.affine_inverse() * point
	var d := Vector2(local.x, -local.y)
	if d.length_squared() < 1e-8:
		d = Vector2(0.0, 1.0)
	return d.normalized()


## Where a ray from the centre of a `view`-sized screen along `dir` meets the rectangle `inset`
## pixels inside its edge.
static func edge_point(view: Vector2, dir: Vector2, inset: float) -> Vector2:
	return HudEdge.edge_point(view, dir, inset)


## The tip of an arrow pointing along `dir` on a `view`-sized screen: EDGE_INSET_PX inside the
## edge, slid along it (HudEdge.clear_of) until the whole arrow clears the `keep_out` rects (the
## HUD's panels drawn now, Hud.overlay_keep_out; none: the plain edge point).
static func tip_for(view: Vector2, dir: Vector2, keep_out: Array = []) -> Vector2:
	return HudEdge.clear_of(edge_point(view, dir, EDGE_INSET_PX), view, EDGE_INSET_PX, footprint(dir), keep_out)


## What an arrow pointing along `dir` covers, relative to its tip: its triangle and outline.
static func footprint(dir: Vector2) -> Rect2:
	var side := Vector2(-dir.y, dir.x) * (ARROW_WIDTH_PX * 0.5)
	var back := -dir * ARROW_LENGTH_PX
	return Rect2().expand(back + side).expand(back - side).grow(1.5)


func _draw() -> void:
	for a: Dictionary in _arrows:
		var tip: Vector2 = a.position
		var dir: Vector2 = a.direction
		var alpha := float(a.alpha)
		HudKit.draw_pointer(self, tip + dir * 1.5, dir, ARROW_LENGTH_PX + 3.0, ARROW_WIDTH_PX + 3.0,
			Color(0.0, 0.0, 0.0, alpha * 0.6))
		HudKit.draw_pointer(self, tip, dir, ARROW_LENGTH_PX, ARROW_WIDTH_PX, Color(COLOR.r, COLOR.g, COLOR.b, alpha))
