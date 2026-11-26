extends HudWidget
class_name HudPlaceMarker
## C3 (decision C3-6): the name-and-icon prompt of the waystones and the forges as the giant comes near - drawn over
## the place itself (the monument's crown, the smithy's chimney), at most MAX_SHOWN of them, nearest first:
##   * a waystone: the standing-stone icon, its name ("Millford waystone") and its state - "Reached: travel here
##     from the map (M)", "Not yet reached: walk up to it", or "Sealed";
##   * a forge: the anvil icon, its name ("Millford's quarry forge") and its state - "Lit: reforge and craft (E)",
##     with what it works beyond iron and hide ("works titan stone"), or "Cold" with its forge's own words.
## Shown within NEAR_M plus NEAR_HEIGHTS x the giant's height (so a stage-8 giant sees them farther off), faded out
## over the last FADE_M, only when the place is in front of the camera; hidden with the HUD (any screen open).
## C3b (decision C3b-5): beyond that, out to FAR_M plus FAR_HEIGHTS x his height, a place is still marked - its icon
## and its name with the distance ("Millford waystone  420 m"), smaller and dimmer (an unreached waystone's grey, a
## cold forge's not at all: it is not a place to go to yet) - at most MAX_FAR of them; the HUD's marks keep one size
## on the screen however far off the place stands, so they read at every stage. Every mark's words are laid out so
## they never cover the HUD's top messages (the region banner, the ability notice, the toasts: their widgets'
## layout_controls()) or each other: a block that would is moved down past what it meets, and a far one that still
## would shows its icon only.
## Full-rect overlay: rectangles and two labels per place (HudKit's batch). Read API: shown() -> [{"kind", "name",
## "state", "distance", "far", "rect"}].

const NEAR_M := 30.0
const NEAR_HEIGHTS := 7.0
const FADE_M := 20.0
const MAX_SHOWN := 2
const FAR_M := 600.0
const FAR_HEIGHTS := 40.0
const MAX_FAR := 4
const STONE := Color(0.55, 0.85, 1.0)
const UNLIT := Color(0.70, 0.72, 0.75)
const FIRE := Color(1.0, 0.62, 0.26)
const SHADE := Color(0, 0, 0, 0.55)
const LABEL_W := 320.0
const LINE_H := 18.0
const WORKS_NAMES := {"titan_stone": "titan stone", "ogre_trophy": "the Ogre King's trophies",
	"warden_wood": "the Rootwarden's heartwood", "warden_stone": "the Warden's stone"}

var _shown: Array = []
var _labels: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudKit.set_z(self, HudKit.Z_OVERLAY)
	for i in (MAX_SHOWN + MAX_FAR) * 2:
		var l := HudKit.label("", HudKit.TEXT if i % 2 == 0 else HudKit.SMALL, Color.WHITE, HudKit.Z_OVERLAY_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(LABEL_W, LINE_H)
		l.visible = false
		add_child(l)
		_labels.append(l)


func shown() -> Array:
	var out: Array = []
	for s: Dictionary in _shown:
		out.append({"kind": s.kind, "name": s.name, "state": s.state, "distance": s.distance, "far": bool(s.far),
			"rect": s.get("rect", Rect2())})
	return out


func _process(_delta: float) -> void:
	_shown = _compute()
	_layout(_shown, _reserved())
	for i in _labels.size():
		_labels[i].visible = false
	for k in _shown.size():
		var s: Dictionary = _shown[k]
		var r: Rect2 = s.get("rect", Rect2())
		if r.size == Vector2.ZERO:
			continue
		var a := float(s.alpha)
		var col: Color = _colour(s)
		var top := _labels[k * 2]
		top.text = str(s.name) if not bool(s.far) else "%s  %d m" % [s.name, roundi(float(s.distance) / 10.0) * 10]
		top.add_theme_font_size_override("font_size", HudKit.SMALL if bool(s.far) else HudKit.TEXT)
		top.add_theme_color_override("font_color", Color(col.r, col.g, col.b, a))
		top.position = r.position
		top.visible = true
		if not bool(s.far):
			var sub := _labels[k * 2 + 1]
			sub.text = str(s.state)
			sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92, a * 0.9))
			sub.position = r.position + Vector2(0, LINE_H)
			sub.visible = true
	queue_redraw()


static func _colour(s: Dictionary) -> Color:
	if str(s.kind) == "forge":
		return FIRE
	return STONE if bool(s.get("known", true)) else UNLIT


## The screen rectangles the HUD's top messages hold now (the other widgets' visible layout controls, above the
## screen's lower third: the region banner, the ability notice, the toasts, the boss bar).
func _reserved() -> Array:
	var out: Array = []
	var parent := get_parent()
	if parent == null:
		return out
	var lower := get_viewport_rect().size.y * 0.66 if is_inside_tree() else 480.0
	for w in parent.get_children():
		if w == self or not (w is Control) or not (w as Control).visible or not w.has_method("layout_controls"):
			continue
		var ctl: Variant = w.call("layout_controls")
		if typeof(ctl) != TYPE_DICTIONARY:
			continue
		for key: Variant in ctl:
			var c: Variant = ctl[key]
			if c is Control and (c as Control).is_visible_in_tree():
				var r := (c as Control).get_global_rect()
				if r.size.x > 0.0 and r.position.y < lower:
					out.append(r.grow(4.0))
	return out


## Places each shown mark's words under its icon (nearest first), moved down past any reserved rectangle or earlier
## block it would cover; a far mark that cannot be placed keeps its icon only (its "rect" empty).
static func _layout(marks: Array, reserved: Array) -> void:
	var taken: Array = reserved.duplicate()
	for s: Dictionary in marks:
		var c: Vector2 = s.screen
		var lines := 1 if bool(s.far) else 2
		var r := Rect2(c + Vector2(-LABEL_W * 0.5, 14.0), Vector2(LABEL_W, LINE_H * lines))
		var icon := Rect2(c - Vector2(12, 12), Vector2(24, 24))
		var placed := false
		for attempt in 8:
			var hit := Rect2()
			for t: Rect2 in taken:
				if t.intersects(r):
					hit = t
					break
			if hit.size == Vector2.ZERO:
				placed = true
				break
			r.position.y = hit.end.y + 2.0
		if not placed and bool(s.far):
			s["rect"] = Rect2()
			taken.append(icon)
			continue
		s["rect"] = r
		taken.append(r)
		taken.append(icon)


func _compute() -> Array:
	var p := player()
	if p == null or p.camera_rig == null or p.camera_rig.camera == null or not p.camera_rig.camera.is_inside_tree():
		return []
	var cam := p.camera_rig.camera
	var h := float(p.profile.get("height_m", 3.66))
	var reach := NEAR_M + NEAR_HEIGHTS * h
	var far := FAR_M + FAR_HEIGHTS * h
	var cands: Array = []
	for n: Node in get_tree().get_nodes_in_group(Waystone.GROUP):
		var w := n as Waystone
		if w == null or not w.is_inside_tree():
			continue
		var at: Vector3 = w.look.crown() if w.look != null else w.global_position + Vector3.UP * 6.0
		cands.append({"kind": "waystone", "node": w, "at": at, "name": w.display_name if w.display_name != "" else "Waystone",
			"state": waystone_state(w), "known": w.is_known(), "open": w.is_open()})
	for n: Node in get_tree().get_nodes_in_group("forges"):
		var f := n as Forge
		if f == null or not f.is_inside_tree() or not f.is_visible_in_tree():
			continue   # (C4: a forge a settlement has not raised yet stands hidden: no mark)
		var at2: Vector3 = f.look.crown() if f.look != null else f.global_position + Vector3.UP * 5.0
		cands.append({"kind": "forge", "node": f, "at": at2, "name": forge_name(f), "state": forge_state(f),
			"known": true, "open": f.is_open()})
	var near_list: Array = []
	var far_list: Array = []
	for c: Dictionary in cands:
		var node := c.node as Node3D
		var d := Vector2(node.global_position.x - p.global_position.x, node.global_position.z - p.global_position.z).length()
		if d > far or cam.is_position_behind(c.at):
			continue
		c["distance"] = d
		c["screen"] = cam.unproject_position(c.at)
		if d <= reach:
			c["far"] = false
			c["alpha"] = clampf((reach - d) / FADE_M, 0.0, 1.0)
			near_list.append(c)
		elif bool(c.open):
			# (far off: a place to go to - a lit forge, an open waystone, reached or not; never a sealed or cold one)
			c["far"] = true
			c["alpha"] = clampf((far - d) / (FADE_M * 4.0), 0.0, 1.0) * 0.85
			if not Rect2(Vector2.ZERO, get_viewport_rect().size).has_point(c.screen as Vector2):
				continue
			far_list.append(c)
	var by_distance := func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance)
	near_list.sort_custom(by_distance)
	far_list.sort_custom(by_distance)
	return near_list.slice(0, MAX_SHOWN) + far_list.slice(0, MAX_FAR)


static func waystone_state(w: Waystone) -> String:
	if not w.is_open():
		return "Sealed"
	if w.is_known():
		return "Reached: travel here from the map (M)"
	return "Not yet reached: walk up to it"


static func forge_name(f: Forge) -> String:
	var n := f.display_name if f.display_name != "" else "Forge"
	return n if n.to_lower().contains("forge") or n.to_lower().contains("smith") or n.to_lower().contains("anvil") \
		else "%s (forge)" % n


static func forge_state(f: Forge) -> String:
	if not f.is_open():
		return "Cold: " + f.closed_message if f.closed_message.length() <= 60 else "Cold"
	var works: Variant = f.get("works")
	var parts := PackedStringArray()
	if typeof(works) == TYPE_PACKED_STRING_ARRAY or typeof(works) == TYPE_ARRAY:
		for wk: Variant in works:
			parts.append(str(WORKS_NAMES.get(str(wk), str(wk).replace("_", " "))))
	return "Lit: reforge and craft (E)" + ("  - works %s" % ", ".join(parts) if not parts.is_empty() else "")


func _draw() -> void:
	for s: Dictionary in _shown:
		var c: Vector2 = s.screen
		var a := float(s.alpha)
		var k := 0.75 if bool(s.far) else 1.0
		if str(s.kind) == "waystone":
			_draw_stone(c, a, k, bool(s.get("known", true)))
		else:
			_draw_anvil(c, a, k)


## A standing stone with its rune band (lit once reached, grey before).
func _draw_stone(c: Vector2, a: float, k := 1.0, known := true) -> void:
	var col := STONE if known else UNLIT
	col.a = a if known else a * 0.6
	draw_rect(Rect2(c + Vector2(-6, -12) * k, Vector2(12, 24) * k), Color(0, 0, 0, 0.55 * a))
	draw_rect(Rect2(c + Vector2(-4, -10) * k, Vector2(8, 20) * k), Color(0.55, 0.58, 0.62, a))
	draw_rect(Rect2(c + Vector2(-4, -3) * k, Vector2(8, 2) * k), col)
	draw_rect(Rect2(c + Vector2(-4, 3) * k, Vector2(8, 2) * k), col)
	draw_rect(Rect2(c + Vector2(-8, 10) * k, Vector2(16, 3) * k), Color(0.4, 0.4, 0.42, a))


## An anvil over a flame.
func _draw_anvil(c: Vector2, a: float, k := 1.0) -> void:
	var col := Color(FIRE.r, FIRE.g, FIRE.b, a)
	var iron := Color(0.75, 0.76, 0.8, a)
	draw_rect(Rect2(c + Vector2(-12, -6) * k, Vector2(24, 14) * k), Color(0, 0, 0, 0.55 * a))
	draw_rect(Rect2(c + Vector2(-10, -4) * k, Vector2(20, 4) * k), iron)
	draw_rect(Rect2(c + Vector2(-3, 0) * k, Vector2(6, 4) * k), iron)
	draw_rect(Rect2(c + Vector2(-7, 4) * k, Vector2(14, 3) * k), iron)
	draw_rect(Rect2(c + Vector2(-2, -11) * k, Vector2(4, 5) * k), col)
	draw_rect(Rect2(c + Vector2(-5, -9) * k, Vector2(3, 3) * k), col)
	draw_rect(Rect2(c + Vector2(3, -9) * k, Vector2(3, 3) * k), col)
