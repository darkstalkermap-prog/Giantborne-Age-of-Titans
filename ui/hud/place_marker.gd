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
## Full-rect overlay: rectangles and two labels per place (HudKit's batch). Read API: shown() -> [{"kind", "name",
## "state", "distance"}].

const NEAR_M := 30.0
const NEAR_HEIGHTS := 7.0
const FADE_M := 20.0
const MAX_SHOWN := 2
const STONE := Color(0.55, 0.85, 1.0)
const FIRE := Color(1.0, 0.62, 0.26)
const SHADE := Color(0, 0, 0, 0.55)
const WORKS_NAMES := {"titan_stone": "titan stone", "ogre_trophy": "the Ogre King's trophies",
	"warden_wood": "the Rootwarden's heartwood", "warden_stone": "the Warden's stone"}

var _shown: Array = []
var _labels: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudKit.set_z(self, HudKit.Z_OVERLAY)
	for i in MAX_SHOWN * 2:
		var l := HudKit.label("", HudKit.TEXT if i % 2 == 0 else HudKit.SMALL, Color.WHITE, HudKit.Z_OVERLAY_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(320, 18)
		l.visible = false
		add_child(l)
		_labels.append(l)


func shown() -> Array:
	var out: Array = []
	for s: Dictionary in _shown:
		out.append({"kind": s.kind, "name": s.name, "state": s.state, "distance": s.distance})
	return out


func _process(_delta: float) -> void:
	_shown = _compute()
	for i in _labels.size():
		_labels[i].visible = false
	for k in _shown.size():
		var s: Dictionary = _shown[k]
		var a := float(s.alpha)
		var col: Color = STONE if s.kind == "waystone" else FIRE
		var top := _labels[k * 2]
		top.text = str(s.name)
		top.add_theme_color_override("font_color", Color(col.r, col.g, col.b, a))
		top.position = (s.screen as Vector2) + Vector2(-160, 14)
		top.visible = true
		var sub := _labels[k * 2 + 1]
		sub.text = str(s.state)
		sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92, a * 0.9))
		sub.position = (s.screen as Vector2) + Vector2(-160, 32)
		sub.visible = true
	queue_redraw()


func _compute() -> Array:
	var p := player()
	if p == null or p.camera_rig == null or p.camera_rig.camera == null or not p.camera_rig.camera.is_inside_tree():
		return []
	var cam := p.camera_rig.camera
	var h := float(p.profile.get("height_m", 3.66))
	var reach := NEAR_M + NEAR_HEIGHTS * h
	var cands: Array = []
	for n: Node in get_tree().get_nodes_in_group(Waystone.GROUP):
		var w := n as Waystone
		if w == null or not w.is_inside_tree():
			continue
		var at: Vector3 = w.look.crown() if w.look != null else w.global_position + Vector3.UP * 6.0
		cands.append({"kind": "waystone", "node": w, "at": at, "name": w.display_name if w.display_name != "" else "Waystone",
			"state": waystone_state(w)})
	for n: Node in get_tree().get_nodes_in_group("forges"):
		var f := n as Forge
		if f == null or not f.is_inside_tree():
			continue
		var at2: Vector3 = f.look.crown() if f.look != null else f.global_position + Vector3.UP * 5.0
		cands.append({"kind": "forge", "node": f, "at": at2, "name": forge_name(f), "state": forge_state(f)})
	var out: Array = []
	for c: Dictionary in cands:
		var node := c.node as Node3D
		var d := Vector2(node.global_position.x - p.global_position.x, node.global_position.z - p.global_position.z).length()
		if d > reach or cam.is_position_behind(c.at):
			continue
		c["distance"] = d
		c["alpha"] = clampf((reach - d) / FADE_M, 0.0, 1.0)
		c["screen"] = cam.unproject_position(c.at)
		out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return out.slice(0, MAX_SHOWN)


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
		if str(s.kind) == "waystone":
			_draw_stone(c, a)
		else:
			_draw_anvil(c, a)


## A standing stone with its rune band and, once reached, its beam.
func _draw_stone(c: Vector2, a: float) -> void:
	var col := Color(STONE.r, STONE.g, STONE.b, a)
	draw_rect(Rect2(c + Vector2(-6, -12), Vector2(12, 24)), Color(0, 0, 0, 0.55 * a))
	draw_rect(Rect2(c + Vector2(-4, -10), Vector2(8, 20)), Color(0.55, 0.58, 0.62, a))
	draw_rect(Rect2(c + Vector2(-4, -3), Vector2(8, 2)), col)
	draw_rect(Rect2(c + Vector2(-4, 3), Vector2(8, 2)), col)
	draw_rect(Rect2(c + Vector2(-8, 10), Vector2(16, 3)), Color(0.4, 0.4, 0.42, a))


## An anvil over a flame.
func _draw_anvil(c: Vector2, a: float) -> void:
	var col := Color(FIRE.r, FIRE.g, FIRE.b, a)
	draw_rect(Rect2(c + Vector2(-12, -6), Vector2(24, 14)), Color(0, 0, 0, 0.55 * a))
	draw_rect(Rect2(c + Vector2(-10, -4), Vector2(20, 4)), Color(0.75, 0.76, 0.8, a))
	draw_rect(Rect2(c + Vector2(-3, 0), Vector2(6, 4)), Color(0.75, 0.76, 0.8, a))
	draw_rect(Rect2(c + Vector2(-7, 4), Vector2(14, 3)), Color(0.75, 0.76, 0.8, a))
	draw_rect(Rect2(c + Vector2(-2, -11), Vector2(4, 5)), col)
	draw_rect(Rect2(c + Vector2(-5, -9), Vector2(3, 3)), col)
	draw_rect(Rect2(c + Vector2(3, -9), Vector2(3, 3)), col)
