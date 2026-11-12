class_name UiKit
extends RefCounted
## Tiny helpers for building the prototype UI in code (flat colours, readable sizes).

const BG := Color(0.07, 0.08, 0.10, 0.82)
const BG_LIGHT := Color(0.16, 0.17, 0.20, 0.92)
const BORDER := Color(1, 1, 1, 0.10)
const TEXT := Color(0.93, 0.93, 0.95)
const MUTED := Color(0.65, 0.67, 0.72)
const HEALTH := Color(0.78, 0.22, 0.20)
const STAMINA := Color(0.36, 0.72, 0.30)
const ESSENCE := Color(0.30, 0.52, 0.92)
const FURY := Color(0.92, 0.55, 0.18)
const WARN := Color(1.0, 0.72, 0.35)
const BAD := Color(1.0, 0.42, 0.38)
const GOOD := Color(0.55, 0.95, 0.55)


static func box(color := BG, radius := 6, border := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border:
		sb.border_color = BORDER
		sb.set_border_width_all(1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(color := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func bar(fill: Color, height := 14) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	var bg := box(Color(0, 0, 0, 0.55), 3, false)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	var fg := box(fill, 3, false)
	fg.content_margin_top = 0
	fg.content_margin_bottom = 0
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func button(text: String, size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	return b


## P39f: the colour of an open tab's title and underline.
const TAB_OPEN := Color(1.0, 0.84, 0.45)
const TAB_OPEN_BG := Color(0.20, 0.22, 0.26, 1.0)
const TAB_UNDERLINE_PX := 3


## P39f (FOLLOWUPS: "the shrine's tab row does not show the open tab"): marks a tab button open or not. The open
## tab stands on a lit box with a gold underline and a gold title; the others keep the plain button with a muted
## title (white when hovered). The focus outline stays the theme's, so the focus and the open tab read apart.
static func set_tab_open(b: Button, open: bool) -> void:
	b.set_meta("tab_open", open)
	var title := TAB_OPEN if open else MUTED
	for c: String in ["font_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(c, title)
	for c: String in ["font_hover_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, TAB_OPEN if open else TEXT)
	for st: String in ["normal", "hover", "pressed", "hover_pressed"]:
		if open:
			b.add_theme_stylebox_override(st, open_tab_box())
		else:
			b.remove_theme_stylebox_override(st)


## True for a tab button set_tab_open() marked open.
static func is_tab_open(b: Button) -> bool:
	return b != null and bool(b.get_meta("tab_open", false))


## The open tab's box: TAB_OPEN_BG with a TAB_UNDERLINE_PX gold underline, with the theme button's content
## margins (an open tab is as big as a closed one: the row does not move when the tab changes).
static func open_tab_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_OPEN_BG
	sb.border_color = TAB_OPEN
	sb.border_width_bottom = TAB_UNDERLINE_PX
	sb.set_corner_radius_all(3)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	var base := ThemeDB.get_default_theme().get_stylebox("normal", "Button")
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, base.get_content_margin(side) if base != null else 4.0)
	return sb
