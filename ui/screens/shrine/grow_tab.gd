extends ShrineTab
## Shrine screen tab "Grow" (P05): the stage this shrine offers (the giant's stage + 1, up to
## the record's max_stage), every requirement with its state (shrine limit and flags, level,
## out of combat, standing still, room to grow), and a Grow button that is enabled only when
## PlayerGrowth.check_growth passes. After a growth it lists what changed (height, reach,
## health, new interactions, learned abilities, a weapon that no longer fits).

const MET := "[x]"
const UNMET := "[ ]"

var _title: Label
var _rows: VBoxContainer
var _result: Label
var grow_button: Button
var _target := 0
## Requirement rows shown now: [{"id", "met": bool, "text"}] (tests read them).
var requirements: Array = []


func tab_title() -> String:
	return "Grow"


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_title = UiKit.label("", 19)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)
	grow_button = UiKit.button("Grow", 20)
	grow_button.pressed.connect(_on_grow)
	add_child(grow_button)
	_result = UiKit.label("", 15)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)


func first_focus() -> Control:
	return grow_button if grow_button != null and not grow_button.disabled else null


## The Grow button (P16; left out of the focus while it is disabled).
func focus_rows() -> Array:
	return [[grow_button]]


func refresh() -> void:
	var s := shrine()
	var p := player()
	if s == null or p == null or _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	requirements = rows_for(s, p)
	_target = s.offered_stage(p)
	var rec := s.record()
	if _target == 0:
		if not bool(rec.get("allows_growth", false)):
			_title.text = "This shrine cannot make you grow."
		elif p.growth != null and p.growth.profile_for_stage(p.growth.stage() + 1).is_empty():
			_title.text = "You have grown as large as you can for now (stage %d)." % p.growth.stage()
		else:
			_title.text = "This shrine can make you grow only to stage %d." % int(rec.get("max_stage", 1))
		grow_button.disabled = true
		return
	var prof: Dictionary = p.growth.profile_for_stage(_target)
	_title.text = "Grow to stage %d: %s (%.1f m)" % [_target, str(prof.get("display_name", "")),
		float(prof.get("height_m", 0.0))]
	for r: Dictionary in requirements:
		var l := UiKit.label("%s %s" % [MET if r.met else UNMET, r.text], 15, UiKit.TEXT if r.met else UiKit.WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(l)
	grow_button.disabled = not s.can_grow(p, _target).ok


## The requirement rows for growing at `s` to its offered stage ([] when it offers none).
static func rows_for(s: Shrine, p: GiantPlayer) -> Array:
	var out: Array = []
	var target := s.offered_stage(p)
	if target == 0 or p.growth == null:
		return out
	var growth: PlayerGrowth = p.growth
	var prof := growth.profile_for_stage(target)
	var rec := s.record()
	out.append({"id": "shrine_max", "met": true,
		"text": "%s can make you grow to stage %d" % [s.display_name(), int(rec.get("max_stage", 1))]})
	var flags_ok := PlayerGrowth.shrine_gate(target, rec, Callable(WorldState, "get_flag"))
	if not (rec.get("growth_requires_flags", []) as Array).is_empty():
		out.append({"id": "flags", "met": flags_ok.ok,
			"text": "The shrine's power is free" if flags_ok.ok else str(flags_ok.message)})
	var level: int = p.controller.level
	var need := int(prof.get("required_level", 1))
	out.append({"id": "level", "met": level >= need,
		"text": "Level %d%s" % [need, " (no level limit here)" if level >= 99 else " (you are level %d)" % level]})
	# P16: the same gate as the growth itself (recent hits, or an aware enemy near the shrine).
	var calm: bool = growth.combat_gate(s).ok
	out.append({"id": "combat", "met": calm, "text": "Out of combat" if calm else PlayerGrowth.default_message("combat")})
	var still: bool = p.controller.state == CombatController.State.LOCOMOTION and p.controller.holding_id == ""
	out.append({"id": "busy", "met": still, "text": "Standing ready, hands free" if still else PlayerGrowth.default_message("busy")})
	var room := growth.check_clearance(prof)
	out.append({"id": "clearance", "met": room.ok, "text": "Room to grow" if room.ok else str(room.message)})
	return out


## The Grow button (also used by tests): Shrine.grow, then the summary or the reason.
func press_grow() -> Dictionary:
	var s := shrine()
	var p := player()
	if s == null or p == null or _target == 0:
		return {"ok": false, "reason": "no_profile", "message": "Nothing to grow to."}
	var out := s.grow(p, _target)
	if out.ok:
		var summary: Dictionary = out.get("summary", {})
		_result.text = "\n".join(summary.get("lines", PackedStringArray()))
		_result.add_theme_color_override("font_color", UiKit.GOOD)
	else:
		_result.text = str(out.get("message", ""))
		_result.add_theme_color_override("font_color", UiKit.WARN)
	screen.notify_changed()
	return out


func _on_grow() -> void:
	press_grow()


func result_text() -> String:
	return _result.text if _result != null else ""


func title_text() -> String:
	return _title.text if _title != null else ""
