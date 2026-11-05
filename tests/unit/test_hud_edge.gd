extends TestSuite
## HudEdge (M4 gate): the edge overlays' shared geometry. A point on the rectangle `inset` px
## inside the screen edge slides along it - past corners, the way that stays nearer its direction
## from the screen centre, then the shorter way - until the overlay's footprint clears every panel
## rect by the margin; a clear point stays; nowhere clear leaves it.
## The panels below are the HUD's at 1280 x 720 (Hud.layout_regions): the tutorial prompt's TIP
## box, the hotbar, the resource panel, the quest tracker.

const VIEW := Vector2(1280, 720)
const INSET := 24.0
const TIP := Rect2(16, 290, 380, 140)
const HOTBAR := Rect2(345, 612, 590, 108)
const RESOURCES := Rect2(16, 570, 324, 134)
const TRACKER := Rect2(924, 14, 340, 118)
const DOT := Rect2(-2, -2, 4, 4)   ## a 4 px footprint centred on the point


static func _inset_of(p: Vector2, view: Vector2) -> float:
	return minf(minf(p.x, view.x - p.x), minf(p.y, view.y - p.y))


## True when `footprint` at `p` keeps the margin clear of every rect.
static func _clear(p: Vector2, footprint: Rect2, rects: Array) -> bool:
	var drawn := Rect2(p + footprint.position, footprint.size)
	for r: Rect2 in rects:
		if drawn.intersects(r.grow(HudEdge.MARGIN_PX - 0.01)):
			return false
	return true


func test_edge_points_and_the_arc_along_the_inset_rectangle() -> void:
	assert_eq(HudEdge.edge_point(VIEW, Vector2(-1, 0), INSET), Vector2(24, 360), "straight left")
	assert_eq(HudEdge.edge_point(VIEW, Vector2(0, 1), INSET), Vector2(640, 696), "straight down")
	assert_eq(HudEdge.edge_point(VIEW, Vector2.ZERO, INSET), VIEW * 0.5, "no direction: the centre")
	var q := Rect2(Vector2(INSET, INSET), VIEW - Vector2(INSET, INSET) * 2.0)
	for p: Vector2 in [Vector2(24, 24), Vector2(640, 24), Vector2(1256, 24), Vector2(1256, 360), Vector2(1256, 696),
			Vector2(640, 696), Vector2(24, 696), Vector2(24, 360)]:
		assert_true(HudEdge.point_at(q, HudEdge.arc_of(q, p)).distance_to(p) < 1e-3, "arc round trip at %s" % p)
	var length := 2.0 * (q.size.x + q.size.y)
	assert_true(HudEdge.point_at(q, length + 10.0).distance_to(Vector2(34, 24)) < 1e-3, "the arc wraps forward")
	assert_true(HudEdge.point_at(q, -10.0).distance_to(Vector2(24, 34)) < 1e-3, "and back")


func test_a_clear_point_stays_and_a_blocked_one_slides_the_way_nearer_its_direction() -> void:
	var left := Vector2(24, 360)
	assert_eq(HudEdge.clear_of(left, VIEW, INSET, DOT, []), left, "nothing to avoid")
	assert_eq(HudEdge.clear_of(Vector2(24, 200), VIEW, INSET, DOT, [TIP]), Vector2(24, 200), "already clear of the TIP box")
	var up := HudEdge.clear_of(Vector2(24, 340), VIEW, INSET, DOT, [TIP])
	assert_true(up.x == 24.0 and up.y < TIP.position.y - HudEdge.MARGIN_PX and up.y > TIP.position.y - 10.0,
		"upper half of the TIP box: just above it (%s)" % up)
	var down := HudEdge.clear_of(Vector2(24, 400), VIEW, INSET, DOT, [TIP])
	assert_true(down.x == 24.0 and down.y > TIP.end.y + HudEdge.MARGIN_PX and down.y < TIP.end.y + 10.0,
		"lower half: just below it (%s)" % down)
	# Straight behind: the hotbar holds the bottom edge's middle and the resource panel its left end
	# round the corner, so the shorter way is to the right of the hotbar.
	var behind := HudEdge.clear_of(Vector2(640, 696), VIEW, INSET, DOT, [HOTBAR, RESOURCES])
	assert_true(behind.y == 696.0 and behind.x > HOTBAR.end.x + HudEdge.MARGIN_PX and behind.x < HOTBAR.end.x + 10.0,
		"behind: along the bottom edge past the hotbar (%s)" % behind)
	var behind_left := HudEdge.clear_of(Vector2(380, 696), VIEW, INSET, DOT, [HOTBAR])
	assert_true(behind_left.y == 696.0 and behind_left.x < HOTBAR.position.x - HudEdge.MARGIN_PX,
		"without the resource panel the nearer end is the hotbar's left (%s)" % behind_left)
	# Behind and to the left with both panels in the way: up the left edge past the resource panel is
	# the longer way (615 px against 436) but keeps the warning on the threat's side (50 degrees off
	# its direction against 64 on the right of the hotbar).
	var left_side := HudEdge.clear_of(Vector2(506, 696), VIEW, INSET, DOT, [HOTBAR, RESOURCES])
	assert_true(left_side.x == 24.0 and left_side.y < RESOURCES.position.y - HudEdge.MARGIN_PX
		and left_side.y > RESOURCES.position.y - 10.0, "behind-left stays on the left (%s)" % left_side)


func test_slides_round_corners_and_respects_the_footprint() -> void:
	# The tracker covers the top-right corner: a point on the top edge near the corner goes round it.
	var near_corner := HudEdge.clear_of(Vector2(1240, 24), VIEW, INSET, DOT, [TRACKER])
	assert_true(near_corner.x == 1256.0 and near_corner.y > TRACKER.end.y + HudEdge.MARGIN_PX,
		"down the right edge below the tracker (%s)" % near_corner)
	var mid_top := HudEdge.clear_of(Vector2(960, 24), VIEW, INSET, DOT, [TRACKER])
	assert_true(mid_top.y == 24.0 and mid_top.x < TRACKER.position.x - HudEdge.MARGIN_PX,
		"left along the top edge (%s)" % mid_top)
	# A footprint reaching 30 px below the point keeps the whole drawing clear.
	var tall := Rect2(-10, -10, 20, 40)
	var p := HudEdge.clear_of(Vector2(24, 300), VIEW, INSET, tall, [TIP])
	assert_true(_clear(p, tall, [TIP]), "the footprint clears the box (%s)" % p)
	assert_true(p.y < TIP.position.y - 30.0, "so the point sits its height above it (%s)" % p)
	for y in range(24, 697, 8):
		for dir_y: float in [-1.0, 1.0]:
			var fp := Rect2(-6, -6 + dir_y * 4.0, 12, 12)
			var moved := HudEdge.clear_of(Vector2(24, y), VIEW, INSET, fp, [TIP, RESOURCES])
			assert_true(_clear(moved, fp, [TIP, RESOURCES]) and absf(_inset_of(moved, VIEW) - INSET) < 1e-3,
				"from (24, %d): clear and still on the edge (%s)" % [y, moved])


func test_nowhere_clear_leaves_the_point() -> void:
	var everything := Rect2(-100, -100, 1500, 1000)
	assert_eq(HudEdge.clear_of(Vector2(24, 360), VIEW, INSET, DOT, [everything]), Vector2(24, 360), "unchanged")
	assert_eq(HudEdge.clear_of(Vector2(24, 360), VIEW, INSET, DOT, ["not a rect", TIP]).x, 24.0,
		"non-rects are ignored")
