class_name HudWidget
extends Control
## Base of the HUD widgets in ui/hud/ (plan §2.10.1). Hud creates one per existing entry of
## HudWidgets.WIDGETS, sets `hud` and adds it as a child, so widgets need no edits to hud.gd.
##
## Rules (M1 lessons): read gameplay state, never change it; connect Events with method
## callables (never capturing lambdas); lay out with set_anchors_and_offsets_preset or explicit
## anchors and offsets; keep to the screen region the plan assigns. Each widget should offer a
## small read API (e.g. visible_text()) so tests need not reach into its nodes.
##
## P16: a widget with a fixed panel reports it in layout_controls() (name -> the panel Control,
## anchored inside the widget's full-screen rect); layout_regions(view) turns those into rects on
## a screen of that size (anchored_rect, from the anchors and offsets), so the HUD layout test can
## check that no two regions overlap at 1280 x 720 and 1920 x 1080, and that the panels really sit
## there. Overlays that draw at points (threat arrows, the objective marker) report none.

var hud: Hud
var _mouse_filter_set := false


## The HUD never takes mouse input (clicks are attacks): every widget starts with
## MOUSE_FILTER_IGNORE when it first enters the tree. _notification runs for every class of
## the hierarchy, so this holds even when a widget defines its own _init; a widget that really
## needs mouse input sets its filter in _ready.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not _mouse_filter_set:
		_mouse_filter_set = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE


## The player the HUD follows, or null (no player yet, or it was freed by a reload).
func player() -> GiantPlayer:
	if hud == null or hud.player == null or not is_instance_valid(hud.player):
		return null
	return hud.player


## The widget's fixed panels: {name: Control} ({} for overlays).
func layout_controls() -> Dictionary:
	return {}


## The widget's fixed screen regions on a `view`-sized screen: {name: Rect2}.
func layout_regions(view: Vector2) -> Dictionary:
	var out := {}
	var controls := layout_controls()
	for key: String in controls:
		out[key] = anchored_rect(controls[key], view)
	return out


## The rect a Control anchored inside a full-screen parent covers on a `view`-sized screen (its
## anchors and offsets; the size a container's content could add is the widget's to keep within).
static func anchored_rect(c: Control, view: Vector2) -> Rect2:
	if c == null:
		return Rect2()
	var left := c.anchor_left * view.x + c.offset_left
	var top := c.anchor_top * view.y + c.offset_top
	var right := c.anchor_right * view.x + c.offset_right
	var bottom := c.anchor_bottom * view.y + c.offset_bottom
	return Rect2(left, top, right - left, bottom - top)
