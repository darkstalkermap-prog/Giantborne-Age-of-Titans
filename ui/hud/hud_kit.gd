class_name HudKit
extends RefCounted
## The HUD's parts, built to be cheap to draw (P27; FOLLOWUPS "Valley views at low still pass 250
## draw calls": the HUD was about 117-120 draw calls of every view).
##
## Godot 4.6's Compatibility canvas renderer draws runs of the same kind of command with the same
## texture as one batch, in draw order (measured under Xvfb, docs/systems/P27.md):
##   * every StyleBoxFlat is a triangle array and polygons never batch (one draw call each, and the
##     next run starts over), as are draw_circle and coloured polygons;
##   * plain rectangles (draw_rect, canvas_item_add_rect, ColorRect) batch, rotated ones too;
##   * a Label's outline glyphs live in another texture than its fill glyphs, so every outlined
##     label costs two calls; a drop shadow without an outline uses the fill glyphs' texture;
##   * each font size has its own glyph texture; a clip rectangle starts a new batch.
## So the HUD draws every panel, bar and shape as rectangles (Box: a StyleBox of rectangles, rect
## shapes in the widgets' _draw), every text with a drop shadow and no outline in one of three sizes,
## never clips, and sorts what it draws with absolute z indices: all rectangles first (Z_BACK), then
## each text size in its own layer, then the edge overlays (threat arrows, the objective marker),
## then the death and help overlays. A view's HUD is then one batch of rectangles plus one per text
## size on screen. Every z is below 0, so the modal screens and the debug panel (z 0, the same canvas
## layer) still draw over the HUD.

const SMALL := 11
const TEXT := 14
const BIG := 18
const TITLE := 26
const SIZES := [SMALL, TEXT, BIG, TITLE]

## Absolute z layers (CanvasItem.z_index with z_as_relative off).
const Z_BACK := -60
## SMALL, TEXT, BIG and TITLE text: Z_TEXT + their index in SIZES.
const Z_TEXT := -59
const Z_OVERLAY := -50
const Z_OVERLAY_TEXT := -49
const Z_DEATH := -40
const Z_DEATH_TEXT := -39
const Z_HELP := -30
const Z_HELP_TEXT := -29

const SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const BORDER := Color(1.0, 1.0, 1.0, 0.10)


## A StyleBox drawn as rectangles: the fill and an optional 1 px border (four thin rectangles), so
## it batches with every other rectangle of the HUD (a StyleBoxFlat is one draw call each).
class Box:
	extends StyleBox

	var bg := Color(0.07, 0.08, 0.10, 0.82)
	var border := Color(0, 0, 0, 0)
	var border_px := 1.0

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		if bg.a > 0.0:
			RenderingServer.canvas_item_add_rect(to_canvas_item, rect, bg)
		if border.a <= 0.0 or border_px <= 0.0 or rect.size.x <= 2.0 * border_px or rect.size.y <= 2.0 * border_px:
			return
		var w := border_px
		var p := rect.position
		var s := rect.size
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p, Vector2(s.x, w)), border)
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p.x, p.y + s.y - w, s.x, w), border)
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p.x, p.y + w, w, s.y - 2.0 * w), border)
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p.x + s.x - w, p.y + w, w, s.y - 2.0 * w), border)


## A Box with UiKit's margins (8 x 6 px), its border on by default.
static func box(color: Color = UiKit.BG, border := true) -> Box:
	var b := Box.new()
	b.bg = color
	b.border = BORDER if border else Color(0, 0, 0, 0)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


## The z layer of text of `size` (the next size up for a size between two).
static func text_z(size: int) -> int:
	for i in SIZES.size():
		if size <= int(SIZES[i]):
			return Z_TEXT + i
	return Z_TEXT + SIZES.size() - 1


## Puts a canvas item on an absolute z layer.
static func set_z(c: CanvasItem, z: int) -> void:
	c.z_as_relative = false
	c.z_index = z


## A panel (PanelContainer with a Box) on Z_BACK that never takes the mouse.
static func panel(color: Color = UiKit.BG, border := true) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_z(p, Z_BACK)
	return p


## A label with a drop shadow and no outline, on its size's text layer (or `z`), never clipping:
## a text wider than the label is trimmed with an ellipsis (set text_overrun_behavior).
static func label(text: String, size := TEXT, color: Color = UiKit.TEXT, z := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_z(l, z if z != 0 else text_z(size))
	return l


## A progress bar of two Boxes (background and fill, no border) on Z_BACK.
static func bar(fill: Color, height := 14) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	var bg := box(Color(0, 0, 0, 0.55), false)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	var fg := box(fill, false)
	fg.content_margin_top = 0
	fg.content_margin_bottom = 0
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_z(b, Z_BACK)
	return b


## A flat rectangle (ColorRect) on Z_BACK.
static func rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_z(r, Z_BACK)
	return r


# --------------------------------------------------------------------------- shapes in _draw

## A diamond (a square turned 45 degrees) of half-diagonal `r` centred on `c`: one rectangle.
static func draw_diamond(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var h := r / sqrt(2.0)
	ci.draw_set_transform(c, PI / 4.0, Vector2.ONE)
	ci.draw_rect(Rect2(-h, -h, 2.0 * h, 2.0 * h), color)
	ci.draw_set_transform(Vector2.ZERO)


## A diamond's outline of `width` px: four thin turned rectangles, one along each edge.
static func draw_diamond_outline(ci: CanvasItem, c: Vector2, r: float, color: Color, width := 2.0) -> void:
	var v := [c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]
	var side := r * sqrt(2.0)
	for k in 4:
		var a: Vector2 = v[k]
		var b: Vector2 = v[(k + 1) % 4]
		ci.draw_set_transform((a + b) * 0.5, (b - a).angle(), Vector2.ONE)
		ci.draw_rect(Rect2(-side * 0.5 - width * 0.5, -width * 0.5, side + width, width), color)
	ci.draw_set_transform(Vector2.ZERO)


## A rhombus pointing along `dir` (unit, screen space) with its tip at `tip`: `length` px long and
## `width` px wide - an arrowhead from one rectangle.
static func draw_pointer(ci: CanvasItem, tip: Vector2, dir: Vector2, length: float, width: float, color: Color) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-8 else Vector2.DOWN
	var centre := tip - d * (length * 0.5)
	# A unit square turned 45 degrees has its corners on the axes at 1/sqrt(2) * sqrt(2) = 1; scale
	# it to the rhombus's half length along d and half width across it.
	var t := Transform2D(d * (length * 0.5), Vector2(-d.y, d.x) * (width * 0.5), centre) \
		* Transform2D(PI / 4.0, Vector2.ZERO)
	ci.draw_set_transform_matrix(t)
	var h := 1.0 / sqrt(2.0)
	ci.draw_rect(Rect2(-h, -h, 2.0 * h, 2.0 * h), color)
	ci.draw_set_transform(Vector2.ZERO)


## A small dot (a square) of half-size `r`.
static func draw_dot(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_rect(Rect2(c - Vector2(r, r), Vector2(2.0 * r, 2.0 * r)), color)


## A string with the HUD's drop shadow (both from the fill glyphs: one texture), left-aligned at
## `pos` (the baseline's left end) or centred on `pos.x` when `centred`.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size: int, color: Color, centred := false) -> void:
	if text == "":
		return
	var font: Font = (ci as Control).get_theme_default_font() if ci is Control else ThemeDB.fallback_font
	var p := pos
	if centred:
		p.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	ci.draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(SHADOW.r, SHADOW.g, SHADOW.b, SHADOW.a * color.a))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# --------------------------------------------------------------------------- the batching rules

## What would break the HUD's batching below `root` ([] = nothing): a StyleBoxFlat (a polygon), a
## label with an outline (two glyph textures) or a shadow outline, a clipping control, or a drawn
## item left on the default z layer (it would draw over the death and help overlays and the text).
## test_hud_draw_rules checks the live HUD with it.
static func batch_breakers(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	_scan(root, root, out)
	return out


static func _scan(n: Node, root: Node, out: PackedStringArray) -> void:
	for c in n.get_children():
		var path := str(root.get_path_to(c))
		if c is Control:
			var ctrl := c as Control
			if ctrl.clip_contents:
				out.append("%s clips its contents" % path)
			for sb_name: String in ["panel", "background", "fill", "normal"]:
				if ctrl.has_theme_stylebox_override(sb_name) and ctrl.get_theme_stylebox(sb_name) is StyleBoxFlat:
					out.append("%s draws a StyleBoxFlat (%s)" % [path, sb_name])
			if ctrl is Label:
				var l := ctrl as Label
				if l.clip_text:
					out.append("%s clips its text" % path)
				if l.get_theme_constant("outline_size") > 0:
					out.append("%s has an outline" % path)
				if l.get_theme_color("font_shadow_color").a > 0.0 and l.get_theme_constant("shadow_outline_size") > 0:
					out.append("%s has a shadow outline" % path)
				if l.z_as_relative or l.z_index >= 0:
					out.append("%s is not on a HUD text layer (z %d)" % [path, l.z_index])
			elif (ctrl is PanelContainer or ctrl is ColorRect or ctrl is ProgressBar) and (ctrl.z_as_relative or ctrl.z_index >= 0):
				out.append("%s is not on a HUD layer (z %d)" % [path, ctrl.z_index])
		_scan(c, root, out)
