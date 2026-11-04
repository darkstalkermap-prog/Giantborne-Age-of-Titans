class_name HudWidget
extends Control
## Base of the HUD widgets in ui/hud/ (plan §2.10.1). Hud creates one per existing entry of
## HudWidgets.WIDGETS, sets `hud` and adds it as a child, so widgets need no edits to hud.gd.
##
## Rules (M1 lessons): read gameplay state, never change it; connect Events with method
## callables (never capturing lambdas); lay out with set_anchors_and_offsets_preset or explicit
## anchors and offsets; keep to the screen region the plan assigns. Each widget should offer a
## small read API (e.g. visible_text()) so tests need not reach into its nodes.

var hud: Hud


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The player the HUD follows, or null (no player yet, or it was freed by a reload).
func player() -> GiantPlayer:
	if hud == null or hud.player == null or not is_instance_valid(hud.player):
		return null
	return hud.player
