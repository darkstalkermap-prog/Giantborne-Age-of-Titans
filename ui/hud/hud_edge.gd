class_name HudEdge
extends RefCounted
## Geometry of the HUD's edge overlays - the threat arrows (P09) and the off-screen objective marker
## (P13) - shared since the M4 gate. Both clamp a direction to a rectangle `inset` px inside the
## screen edge (edge_point); clear_of() then slides that point along the same rectangle until what
## the overlay draws there clears every fixed HUD panel on screen (Hud.overlay_keep_out: the
## tutorial prompt, the hotbar, the quest tracker, the boss bar, ...), the way that keeps it nearer
## its direction. So an edge warning is never hidden under a panel nor drawn over one, and it stays
## `inset` px inside the edge, pointing the way it did. Pure: no scene access.

## Space kept between an overlay's drawing and a panel.
const MARGIN_PX := 4.0
## How far past a blocked stretch's end a slid point lands.
const STEP_PX := 0.5


## Where a ray from the centre of a `view`-sized screen along `dir` meets the rectangle `inset`
## pixels inside its edge (the centre itself for a zero direction).
static func edge_point(view: Vector2, dir: Vector2, inset: float) -> Vector2:
	var c := view * 0.5
	var h := Vector2(maxf(c.x - inset, 0.0), maxf(c.y - inset, 0.0))
	var tx := h.x / absf(dir.x) if absf(dir.x) > 1e-6 else INF
	var ty := h.y / absf(dir.y) if absf(dir.y) > 1e-6 else INF
	var t := minf(tx, ty)
	return c if is_inf(t) else c + dir * t


## `point` (on the rectangle `inset` px inside a `view`-sized screen) moved along that rectangle,
## past corners, to the first place either way where `footprint` (the overlay's drawing, as a rect
## relative to the point) keeps MARGIN_PX clear of every rect in `keep_out`. Of the two, the one
## seen from the screen centre closer to the point's own direction wins (a threat behind and to the
## left stays on the left), then the shorter one. Returned unchanged when it already is clear, or
## when no place on the rectangle is.
static func clear_of(point: Vector2, view: Vector2, inset: float, footprint: Rect2, keep_out: Array) -> Vector2:
	# The point may not enter a panel grown by the margin and by the footprint (Minkowski sum).
	var blocked: Array[Rect2] = []
	for r: Variant in keep_out:
		if typeof(r) != TYPE_RECT2:
			continue
		var g := (r as Rect2).grow(MARGIN_PX)
		blocked.append(Rect2(g.position - footprint.end, g.size + footprint.size))
	if _blocker(point, blocked) < 0:
		return point
	var q := Rect2(Vector2(inset, inset), view - Vector2(inset, inset) * 2.0)
	var length := 2.0 * (q.size.x + q.size.y)
	if q.size.x <= 0.0 or q.size.y <= 0.0:
		return point
	var s0 := arc_of(q, point)
	var ahead := _slide(q, s0, blocked, true)
	var back := _slide(q, s0, blocked, false)
	var d_ahead := ahead - s0
	var d_back := s0 - back
	if d_ahead >= length and d_back >= length:
		return point
	# Seen from the centre, the angle grows steadily round the rectangle, so each way's first clear
	# place is that way's nearest in angle too.
	var c := view * 0.5
	var a := point_at(q, ahead)
	var b := point_at(q, back)
	var err_a := absf((a - c).angle_to(point - c))
	var err_b := absf((b - c).angle_to(point - c))
	if absf(err_a - err_b) > 1e-6:
		return a if err_a < err_b else b
	return a if d_ahead <= d_back else b


## The arc length of `p` along `q`'s boundary, clockwise from its top-left corner (top edge, right,
## bottom, left); a point off the boundary counts at its nearest edge.
static func arc_of(q: Rect2, p: Vector2) -> float:
	var w := q.size.x
	var h := q.size.y
	var d_top := absf(p.y - q.position.y)
	var d_right := absf(p.x - q.end.x)
	var d_bottom := absf(p.y - q.end.y)
	var d_left := absf(p.x - q.position.x)
	var m := minf(minf(d_top, d_right), minf(d_bottom, d_left))
	if m == d_top:
		return clampf(p.x - q.position.x, 0.0, w)
	if m == d_right:
		return w + clampf(p.y - q.position.y, 0.0, h)
	if m == d_bottom:
		return w + h + clampf(q.end.x - p.x, 0.0, w)
	return 2.0 * w + h + clampf(q.end.y - p.y, 0.0, h)


## The point at arc length `s` (any real number: it wraps) along `q`'s boundary (see arc_of).
static func point_at(q: Rect2, s: float) -> Vector2:
	var w := q.size.x
	var h := q.size.y
	s = fposmod(s, 2.0 * (w + h))
	if s < w:
		return Vector2(q.position.x + s, q.position.y)
	s -= w
	if s < h:
		return Vector2(q.end.x, q.position.y + s)
	s -= h
	if s < w:
		return Vector2(q.end.x - s, q.end.y)
	return Vector2(q.position.x, q.end.y - (s - w))


## The index of a rect of `blocked` that holds `p` strictly inside, or -1.
static func _blocker(p: Vector2, blocked: Array[Rect2]) -> int:
	for i in blocked.size():
		var b := blocked[i]
		if p.x > b.position.x and p.x < b.end.x and p.y > b.position.y and p.y < b.end.y:
			return i
	return -1


## Slides from arc length `s` (clockwise when `forward`) out of every blocked rect it meets: the
## first clear arc length, unwrapped (it may pass the length of the loop; a full loop or more
## means nowhere is clear).
static func _slide(q: Rect2, s: float, blocked: Array[Rect2], forward: bool) -> float:
	var length := 2.0 * (q.size.x + q.size.y)
	var start := s
	for i in blocked.size() * 4 + 8:
		var k := _blocker(point_at(q, s), blocked)
		if k < 0:
			return s
		var base := s - fposmod(s, length)
		var exit := base + _exit_arc(q, fposmod(s, length), blocked[k], forward)
		s = exit + (STEP_PX if forward else -STEP_PX)
		if absf(s - start) >= length:
			break
	return start + (length if forward else -length)


## Where the edge of `q` that arc length `s` lies on leaves rect `b`, going clockwise (`forward`)
## or back: an arc length on that edge (its corner when `b` covers the rest of it).
static func _exit_arc(q: Rect2, s: float, b: Rect2, forward: bool) -> float:
	var w := q.size.x
	var h := q.size.y
	if s < w:   # top edge, left to right
		return minf(b.end.x - q.position.x, w) if forward else maxf(b.position.x - q.position.x, 0.0)
	if s < w + h:   # right edge, top to bottom
		return w + (minf(b.end.y - q.position.y, h) if forward else maxf(b.position.y - q.position.y, 0.0))
	if s < 2.0 * w + h:   # bottom edge, right to left
		return w + h + (minf(q.end.x - b.position.x, w) if forward else maxf(q.end.x - b.end.x, 0.0))
	# left edge, bottom to top
	return 2.0 * w + h + (minf(q.end.y - b.position.y, h) if forward else maxf(q.end.y - b.end.y, 0.0))
