extends HudWidget
## The new-ability notice (plan §2.10.1; P12): centre, (-260..260, -250..-212) above the hotbar.
## Every Events.ability_learned (a level-up, a growth unlock, a quest or dialogue reward) is queued
## and shown as "New ability: Runic Bolt [6]" ([key] = the slot's binding; "choose a slot at a
## shrine" when it was not slotted), one at a time for SHOW_S plus a FADE_S fade, but only while the
## player is alive and out of combat (ResourcePool.in_combat() false): a notice learned mid-fight
## waits until the fight is over.

const SHOW_S := 3.0
const FADE_S := 0.5
const MAX_FRAME_S := 0.1

var _panel: PanelContainer
var _label: Label
var _queue: Array = []   ## [{"id", "slot"}], oldest first
var _left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UiKit.panel(Color(0.08, 0.07, 0.03, 0.88))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = -250
	_panel.offset_bottom = -212
	add_child(_panel)
	_label = UiKit.label("", 19, Color(1.0, 0.86, 0.45))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_label)
	_panel.visible = false
	Events.ability_learned.connect(_on_ability_learned)


## "New ability: Runic Bolt [6]" for a learned action and the slot it went into ("" = none).
static func notice_text(action_id: String, slot_key: String) -> String:
	var def := GameData.get_action(action_id)
	var label := def.display_name if def != null else action_id
	if slot_key == "":
		return "New ability: %s (choose a slot at a shrine)" % label
	return "New ability: %s [%s]" % [label, Progression.slot_key_label(slot_key)]


## True while `p` is in no state to read a notice: dead, or fighting (hits exchanged recently).
static func should_wait(p: GiantPlayer) -> bool:
	if p == null or p.entity == null or p.entity.combatant == null:
		return true
	return not p.entity.is_alive() or p.entity.combatant.pools.in_combat()


## What the notice shows now ("" while hidden).
func visible_text() -> String:
	return _label.text if _panel != null and _panel.visible else ""


## Notices waiting to be shown (not counting the one on screen).
func pending_count() -> int:
	return _queue.size()


func _on_ability_learned(_tick: int, action_id: String, slot_key: String) -> void:
	_queue.append({"id": action_id, "slot": slot_key})


func _process(delta: float) -> void:
	if _panel.visible:
		_left -= minf(delta, MAX_FRAME_S)
		if _left <= 0.0:
			_panel.visible = false
		elif _left < FADE_S:
			_panel.modulate.a = _left / FADE_S
		return
	if _queue.is_empty() or should_wait(player()):
		return
	var next: Dictionary = _queue.pop_front()
	_label.text = notice_text(str(next.id), str(next.slot))
	_left = SHOW_S + FADE_S
	_panel.modulate.a = 1.0
	_panel.visible = true
