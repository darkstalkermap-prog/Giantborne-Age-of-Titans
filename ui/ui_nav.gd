class_name UiNav
extends RefCounted
## Pad and keyboard navigation of the modal screens (P16, plan §3.18).
##
## - ensure_pad_actions(): Godot 4.6's default input map has no pad button in ui_accept or
##   ui_cancel, so a controller could move the focus (D-pad and left stick are in ui_up / down /
##   left / right) but never press or back out. Pad A joins ui_accept (press the focused control)
##   and pad B joins ui_cancel (ScreenStack: cancel the top screen). main.gd and every ScreenStack
##   call it; it is idempotent.
## - link_rows(rows): explicit focus neighbours from rows of controls (top to bottom, each row left
##   to right). Controls that cannot take the focus (hidden, disabled buttons) are left out; up and
##   down move between rows (to the control nearest horizontally once the layout has run, else the
##   same index), left and right within a row, Tab and Shift+Tab in reading order, and every
##   direction wraps around at the ends. A screen lists its rows in UiScreen.focus_rows().
## - keep_focus(screen): puts the focus back inside a screen when it was lost or sits on a control
##   that cannot have it any more (a button that became disabled, a page that was hidden).

## The pad buttons the menu actions gain: [action, JoyButton].
const PAD_ACTIONS := [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]


## Adds pad A to ui_accept and pad B to ui_cancel unless they are there already.
static func ensure_pad_actions() -> void:
	for entry: Array in PAD_ACTIONS:
		var action := str(entry[0])
		if not InputMap.has_action(action) or has_pad_button(action, int(entry[1])):
			continue
		var ev := InputEventJoypadButton.new()
		ev.button_index = entry[1]
		ev.device = -1
		InputMap.action_add_event(action, ev)


## True when `action` has a joypad button event for `button`.
static func has_pad_button(action: String, button: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and int((e as InputEventJoypadButton).button_index) == button:
			return true
	return false


## True when `c` can take the focus now: a live Control in the tree, visible, focusable, and not
## a disabled button.
static func focusable(c: Variant) -> bool:
	if not (c is Control) or not is_instance_valid(c):
		return false
	var ctrl := c as Control
	if not ctrl.is_inside_tree() or not ctrl.is_visible_in_tree() or ctrl.focus_mode == Control.FOCUS_NONE:
		return false
	return not (ctrl is BaseButton and (ctrl as BaseButton).disabled)


## Wires the focus neighbours of `rows` (an Array of rows; a row is an Array of Controls, or one
## Control). Returns the rows kept (only focusable controls; empty rows dropped), so callers and
## tests can see the order.
static func link_rows(rows: Array) -> Array:
	var kept: Array = []
	for row: Variant in rows:
		var items: Array = row if row is Array else [row]
		var r: Array = []
		for c: Variant in items:
			if focusable(c) and not r.has(c):
				r.append(c)
		if not r.is_empty():
			kept.append(r)
	if kept.is_empty():
		return kept
	var flat: Array = []
	for r: Array in kept:
		flat.append_array(r)
	var n := kept.size()
	for ri in n:
		var r: Array = kept[ri]
		var above: Array = kept[(ri - 1 + n) % n]
		var below: Array = kept[(ri + 1) % n]
		for i in r.size():
			var c: Control = r[i]
			c.focus_neighbor_left = c.get_path_to(r[(i - 1 + r.size()) % r.size()])
			c.focus_neighbor_right = c.get_path_to(r[(i + 1) % r.size()])
			c.focus_neighbor_top = c.get_path_to(_pick(above, c, i))
			c.focus_neighbor_bottom = c.get_path_to(_pick(below, c, i))
	for i in flat.size():
		var c: Control = flat[i]
		c.focus_next = c.get_path_to(flat[(i + 1) % flat.size()])
		c.focus_previous = c.get_path_to(flat[(i - 1 + flat.size()) % flat.size()])
	return kept


## The control of `row` that `from` (index i in its own row) moves to: the one whose centre is
## nearest horizontally once every rect is laid out, else the same index (the row's last when it
## is shorter).
static func _pick(row: Array, from: Control, i: int) -> Control:
	if row.size() == 1:
		return row[0]
	var from_rect := from.get_global_rect()
	var laid_out := from_rect.size.x > 0.0
	for c: Control in row:
		laid_out = laid_out and c.get_global_rect().size.x > 0.0
	if not laid_out:
		return row[mini(i, row.size() - 1)]
	var best: Control = row[0]
	var best_d := INF
	var x := from_rect.get_center().x
	for c: Control in row:
		var d := absf(c.get_global_rect().get_center().x - x)
		if d < best_d - 0.5:
			best = c
			best_d = d
	return best


## Gives `screen` the focus back when nothing inside it has it, or its owner cannot take it now:
## first_focus() when that can take it, else the first focusable control of focus_rows(). Returns
## the control that has the focus afterwards (null when none can).
static func keep_focus(screen: Control) -> Control:
	if screen == null or not is_instance_valid(screen) or not screen.is_inside_tree():
		return null
	var owner := screen.get_viewport().gui_get_focus_owner()
	if owner != null and screen.is_ancestor_of(owner) and focusable(owner):
		return owner
	var candidates: Array = []
	if screen.has_method("first_focus"):
		candidates.append(screen.call("first_focus"))
	if screen.has_method("focus_rows"):
		for row: Variant in screen.call("focus_rows"):
			candidates.append_array(row if row is Array else [row])
	for c: Variant in candidates:
		if focusable(c) and screen.is_ancestor_of(c):
			(c as Control).grab_focus()
			return c
	return null


## Tabbed screens (pause menu, shrine): -1 for a pad LB press, +1 for RB, 0 for anything else.
static func page_step(event: InputEvent) -> int:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed:
		return 0
	match b.button_index:
		JOY_BUTTON_LEFT_SHOULDER:
			return -1
		JOY_BUTTON_RIGHT_SHOULDER:
			return 1
	return 0


## The focus owner of `node`'s viewport (null when none).
static func focus_owner(node: Node) -> Control:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return null
	return node.get_viewport().gui_get_focus_owner()


## The footer line the screen stack shows while a menu is open: how to move, select and go back
## with the device the player is using.
static func hint_text(pad: bool) -> String:
	if pad:
		return "D-pad / left stick: move     A: select     B: back"
	return "Arrows / Tab: move     Enter: select     Esc: back     (or use the mouse)"
