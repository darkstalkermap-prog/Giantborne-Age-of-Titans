class_name HudCompass
extends HudWidget
## The compass (P27; plan M6-M9 §2.14, §3.10 design 3): a heading strip at the top centre,
## (-HALF_WIDTH..HALF_WIDTH, 4..34), turned with the camera: ticks every 15 degrees and N, E, S, W,
## and on it
##   * the tracked quest's objective as gold diamonds - one per marker of a multi-marker stage
##     (Quests.tracked_objective()'s positions) - held at the strip's ends when they are behind;
##   * up to LEAD_LIMIT leads (Quests.leads(): the main thread's markers while another quest is
##     tracked) as hollow diamonds;
##   * the MAX_POIS nearest POIs on the map (Discovery: found or revealed) within RADIUS_M (unscaled,
##     whatever the giant's size) whose record has compass: true, as small squares in their kind's
##     colour;
##   * undiscovered POIs as "?": within UNKNOWN_M, or within SKYLINE_UNKNOWN_M when their landmark is
##     on the skyline (at most MAX_POIS, nearest first);
##   * the map pin (map.pin) as a red pin, at any distance, on the level it was placed on.
## Hidden where the level has no world index (the sandbox, the title) and while the HUD is hidden.
## Drawn by HudKit's rules: every mark a rectangle on the HUD's rectangle layer, the letters and "?"
## shadowed text on the small text layer.
## Read API: markers_now(), heading_now(), visible_text(); the geometry is static (markers_for,
## heading_of, bearing_of, offset_deg).
## P39f (FOLLOWUPS: "compass markers draw over its direction letters"): the strip has two rows - the marks
## (diamonds, squares, the pin and the "?") on the upper one round MARK_Y, the letters on the lower one at
## LETTER_BASELINE - so no mark ever covers a letter, whatever the bearing (a red pin sat on the N of "NE",
## "?" on "NW" and "E"). The strip is 30 px tall (4..34; it was 24), still 10 px above the target frame and
## the boss bar; the ticks stand between the letters. mark_rect() and letter_rect() are where each is drawn.

const HALF_WIDTH := 270.0
const TOP := 4.0
const HEIGHT := 30.0
## P39f: the marks' row (its centre, px from the strip's top) and the letters' baseline; a letter's ink is
## LETTER_CAP_PX tall above its baseline (HudKit.SMALL caps in the HUD's font), and the "?" is drawn on the
## marks' row with its baseline UNKNOWN_BASELINE.
const MARK_Y := 9.0
const LETTER_BASELINE := 27.0
const LETTER_CAP_PX := 9.0
const UNKNOWN_BASELINE := 13.0
## The strip spans the heading +- FIELD_DEG / 2.
const FIELD_DEG := 180.0
const RADIUS_M := 600.0
const MAX_POIS := 6
const UNKNOWN_M := 250.0
const SKYLINE_UNKNOWN_M := 1000.0
const LEAD_LIMIT := 3
## Ends of the strip where held objective diamonds sit (px from the centre).
const EDGE_PX := HALF_WIDTH - 10.0

const BG := Color(0.05, 0.06, 0.08, 0.62)
const TICK := Color(0.85, 0.87, 0.9, 0.55)
const NORTH := Color(1.0, 0.45, 0.35)
const OBJECTIVE := Color(1.0, 0.82, 0.30)
const LEAD := Color(1.0, 0.86, 0.55, 0.9)
const PIN := Color(1.0, 0.36, 0.32)
const UNKNOWN := Color(0.80, 0.82, 0.86)
## POI kind -> its square's colour.
const KIND_COLORS := {
	"settlement": Color(0.95, 0.85, 0.55), "shrine": Color(0.55, 0.85, 1.0), "waystone": Color(0.55, 0.85, 1.0),
	"ruin": Color(0.75, 0.70, 0.62), "landmark": Color(0.85, 0.80, 0.70), "camp": Color(1.0, 0.55, 0.40),
	"lair": Color(1.0, 0.45, 0.35), "boss": Color(1.0, 0.35, 0.30), "forge": Color(1.0, 0.65, 0.30),
	"gate": Color(0.80, 0.75, 0.90), "vista": Color(0.70, 0.95, 0.70), "exit": Color(0.95, 0.95, 0.95),
	"secret": Color(0.70, 0.60, 0.90),
}

var _strip: Control
var _letters: Control
var _markers: Array = []
var _heading := 0.0
var _pois: Dictionary = {}
var _pois_level := "~"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_strip = Control.new()
	_strip.name = "Strip"
	_strip.draw.connect(_draw_strip)
	_strip.anchor_left = 0.5
	_strip.anchor_right = 0.5
	_strip.offset_left = -HALF_WIDTH
	_strip.offset_right = HALF_WIDTH
	_strip.offset_top = TOP
	_strip.offset_bottom = TOP + HEIGHT
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.visible = false
	add_child(_strip)
	_letters = Control.new()
	_letters.name = "Letters"
	_letters.draw.connect(_draw_letters)
	_letters.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_letters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudKit.set_z(_letters, HudKit.text_z(HudKit.SMALL))
	_strip.add_child(_letters)


func _process(_delta: float) -> void:
	var p := player()
	var idx := Quests.level_index()
	if p == null or idx == null or p.camera_rig == null or not p.is_inside_tree():
		_strip.visible = false
		_markers = []
		return
	_strip.visible = true
	var level_id := idx.level_id
	if level_id != _pois_level:
		_pois_level = level_id
		var d := Discovery.of_tree(get_tree())
		_pois = d.pois if d != null and d.level_id == level_id else Discovery.poi_table(level_id)
	var offset := _root_offset()
	var pos := p.global_position - offset
	_heading = heading_of(p.camera_rig.yaw)
	var objective := Quests.tracked_objective() if Quests.is_active() else {}
	var leads: Array = []
	if Quests.is_active():
		for l: Dictionary in Quests.leads():
			leads.append({"marker_id": l.marker_id, "position": (l.position as Vector3) - offset})
	_markers = markers_for(pos, _heading, _pois, WorldState.flags, objective_positions(objective, offset), leads,
		Discovery.pin_on(WorldState.flags, level_id))
	_strip.queue_redraw()
	_letters.queue_redraw()


func _root_offset() -> Vector3:
	var root := get_tree().get_first_node_in_group(LevelRoot.GROUP) as Node3D
	return root.global_position if root != null and root.is_inside_tree() else Vector3.ZERO


func layout_controls() -> Dictionary:
	return {"compass": _strip}


## The marks on the strip now ([] while hidden): see markers_for.
func markers_now() -> Array:
	return _markers if _strip != null and _strip.visible else []


## The heading shown now (degrees clockwise from north).
func heading_now() -> float:
	return _heading


## "N 12 | objective -30 | ? 45 | ..." (tests, logs; "" while hidden).
func visible_text() -> String:
	if _strip == null or not _strip.visible:
		return ""
	var parts := PackedStringArray(["%s %d" % [cardinal(_heading), roundi(_heading)]])
	for m: Dictionary in _markers:
		parts.append("%s %d" % [m.kind, roundi(float(m.offset))])
	return " | ".join(parts)


# --------------------------------------------------------------------------- geometry (pure)

## The heading of a camera yaw (Godot's: 0 faces -Z, north), in degrees clockwise from north, 0..360.
static func heading_of(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)


## The bearing from `from` to `to` on the ground plane, degrees clockwise from north (-Z), 0..360.
static func bearing_of(from: Vector3, to: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(to.x - from.x, -(to.z - from.z))), 360.0)


## How far a bearing lies right (+) or left (-) of the heading, -180..180.
static func offset_deg(bearing: float, heading: float) -> float:
	return wrapf(bearing - heading, -180.0, 180.0)


## The strip's x (px from its centre) of an offset; INF outside the field.
static func x_of(offset: float) -> float:
	if absf(offset) > FIELD_DEG * 0.5:
		return INF
	return offset / (FIELD_DEG * 0.5) * HALF_WIDTH


## "N", "NE", ... for a heading.
static func cardinal(heading: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[int(roundf(fposmod(heading, 360.0) / 45.0)) % 8]


## The positions a tracked objective points at (level space): every marker of a multi-marker stage,
## else its position ([] without one).
static func objective_positions(objective: Dictionary, root_offset := Vector3.ZERO) -> Array:
	var out: Array = []
	var positions: Variant = objective.get("positions", [])
	if typeof(positions) == TYPE_ARRAY and (positions as Array).size() > 1:
		for v: Variant in positions:
			if typeof(v) == TYPE_VECTOR3 and (v as Vector3).is_finite():
				out.append((v as Vector3) - root_offset)
	if out.is_empty():
		var p: Variant = objective.get("position", Vector3.INF)
		if typeof(p) == TYPE_VECTOR3 and (p as Vector3).is_finite():
			out.append((p as Vector3) - root_offset)
	return out


## The marks of the strip for a giant at `pos` (level space) facing `heading`: [{"kind" (objective |
## lead | poi | unknown | pin), "id", "bearing", "offset" (-180..180), "x" (px from the centre; held
## objectives at +-EDGE_PX), "held" (an objective outside the field), "distance", "color"}], in the
## order they are drawn (POIs and unknowns, then the pin, the leads and the objectives on top).
## `pois`: Discovery.poi_table(); `objectives`: positions (objective_positions); `leads`:
## [{"marker_id", "position"}]; `pin`: Vector2 (x, z) or Vector2.INF.
static func markers_for(pos: Vector3, heading: float, pois: Dictionary, flags: Dictionary, objectives: Array,
		leads: Array, pin: Vector2) -> Array:
	var out: Array = []
	var known: Array = []
	var unknown: Array = []
	for id: String in pois:
		var info: Dictionary = pois[id]
		if not bool(info.get("compass", true)) or str(info.get("kind", "")) == "secret":
			continue
		var at: Vector3 = info.position
		if not at.is_finite():
			continue
		var d := Discovery.flat_distance(pos, at)
		if Discovery.is_known(flags, id):
			if d <= RADIUS_M:
				known.append([d, id])
		elif d <= UNKNOWN_M or (bool(info.get("skyline", false)) and d <= SKYLINE_UNKNOWN_M):
			unknown.append([d, id])
	known.sort()
	unknown.sort()
	for pair: Array in known.slice(0, MAX_POIS):
		var info: Dictionary = pois[pair[1]]
		_add(out, "poi", str(pair[1]), pos, info.position, heading, false,
			KIND_COLORS.get(str(info.get("kind", "")), UNKNOWN))
	for pair: Array in unknown.slice(0, MAX_POIS):
		_add(out, "unknown", str(pair[1]), pos, (pois[pair[1]] as Dictionary).position, heading, false, UNKNOWN)
	if pin.is_finite():
		_add(out, "pin", Discovery.PIN_FLAG, pos, Vector3(pin.x, pos.y, pin.y), heading, false, PIN)
	for l: Variant in leads.slice(0, LEAD_LIMIT):
		if typeof(l) == TYPE_DICTIONARY and typeof((l as Dictionary).get("position")) == TYPE_VECTOR3:
			_add(out, "lead", str(l.get("marker_id", "")), pos, l.position, heading, false, LEAD)
	for i in objectives.size():
		_add(out, "objective", "objective_%d" % i, pos, objectives[i], heading, true, OBJECTIVE)
	return out


static func _add(out: Array, kind: String, id: String, from: Vector3, to: Vector3, heading: float, hold: bool,
		color: Color) -> void:
	var bearing := bearing_of(from, to)
	var off := offset_deg(bearing, heading)
	var x := x_of(off)
	var held := false
	if not is_finite(x):
		if not hold:
			return
		x = EDGE_PX * signf(off) if off != 0.0 else EDGE_PX
		held = true
	out.append({"kind": kind, "id": id, "bearing": bearing, "offset": off, "x": x, "held": held,
		"distance": Discovery.flat_distance(from, to), "color": color})


# --------------------------------------------------------------------------- drawing
# The strip and the letters are plain Controls drawn from their draw signals (their own canvas items:
# the strip on the HUD's rectangle layer, the letters on the small text layer).

## The strip: its band, ticks, the centre notch and every mark - rectangles only.
func _draw_strip() -> void:
	var s := _strip
	var w := s.size.x
	var h := s.size.y
	var cx := w * 0.5
	s.draw_rect(Rect2(Vector2.ZERO, s.size), BG)
	s.draw_rect(Rect2(0, h - 1.0, w, 1.0), Color(1, 1, 1, 0.12))
	var deg := int(floor((_heading - FIELD_DEG * 0.5) / 15.0)) * 15
	while deg <= int(ceil(_heading + FIELD_DEG * 0.5)):
		var x := x_of(offset_deg(float(deg), _heading))
		# P39f: the letters stand at every 45 degrees, the ticks between them
		if is_finite(x) and posmod(deg, 45) != 0:
			s.draw_rect(Rect2(cx + x - 0.5, h - 4.0, 1.0, 3.0), TICK)
		deg += 15
	# the centre notch: the way the camera looks
	s.draw_rect(Rect2(cx - 1.0, 0.0, 2.0, 5.0), Color(1, 1, 1, 0.85))
	for m: Dictionary in _markers:
		var x := cx + float(m.x)
		var c: Color = m.color
		var mid := Vector2(x, MARK_Y)
		# P39f: every mark on the upper row, inside mark_rect(kind, x)
		match str(m.kind):
			"objective":
				HudKit.draw_diamond(s, mid, 7.0, Color(0, 0, 0, 0.55))
				HudKit.draw_diamond(s, mid, 5.5, c if not bool(m.held) else Color(c.r, c.g, c.b, 0.6))
			"lead":
				HudKit.draw_diamond_outline(s, mid, 5.0, c, 2.0)
			"poi":
				s.draw_rect(Rect2(x - 4.0, MARK_Y - 4.0, 8.0, 8.0), Color(0, 0, 0, 0.55))
				s.draw_rect(Rect2(x - 3.0, MARK_Y - 3.0, 6.0, 6.0), c)
			"pin":
				s.draw_rect(Rect2(x - 1.0, MARK_Y - 1.0, 2.0, 7.0), Color(0.15, 0.1, 0.1, 0.9))
				HudKit.draw_diamond(s, Vector2(x, MARK_Y - 2.5), 4.5, c)


## The letters N E S W (the in-between ones in grey) on the lower row and the "?" of undiscovered places on
## the marks' row (P39f).
func _draw_letters() -> void:
	var s := _letters
	var cx := s.size.x * 0.5
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for k in 8:
		var x := x_of(offset_deg(k * 45.0, _heading))
		if not is_finite(x):
			continue
		var color := NORTH if k == 0 else (Color(0.95, 0.95, 0.97) if k % 2 == 0 else Color(0.7, 0.72, 0.76))
		HudKit.draw_text(s, Vector2(cx + x, LETTER_BASELINE), names[k], HudKit.SMALL, color, true)
	for m: Dictionary in _markers:
		if str(m.kind) == "unknown":
			HudKit.draw_text(s, Vector2(cx + float(m.x), UNKNOWN_BASELINE), "?", HudKit.SMALL, UNKNOWN, true)


## P39f: where a mark of `kind` centred at `x` (px from the strip's left) is drawn, in the strip's coordinates:
## every kind on the marks' row, above the letters' row.
static func mark_rect(kind: String, x: float) -> Rect2:
	match kind:
		"objective":
			return Rect2(x - 7.0, MARK_Y - 7.0, 14.0, 14.0)
		"lead":
			return Rect2(x - 6.0, MARK_Y - 6.0, 12.0, 12.0)
		"poi":
			return Rect2(x - 4.0, MARK_Y - 4.0, 8.0, 8.0)
		"pin":
			return Rect2(x - 4.5, MARK_Y - 7.0, 9.0, 13.0)
		"unknown":
			return Rect2(x - 4.0, UNKNOWN_BASELINE - LETTER_CAP_PX, 8.0, LETTER_CAP_PX + 1.0)
	return Rect2(x - 7.0, MARK_Y - 7.0, 14.0, 14.0)


## P39f: where a direction letter (`text`, centred at `x`) is drawn: its ink above LETTER_BASELINE, as wide as
## `font` sets it at HudKit.SMALL (plus its 1 px shadow).
static func letter_rect(text: String, x: float, font: Font) -> Rect2:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HudKit.SMALL).x if font != null else 14.0
	return Rect2(x - w * 0.5, LETTER_BASELINE - LETTER_CAP_PX, w + 1.0, LETTER_CAP_PX + 2.0)
