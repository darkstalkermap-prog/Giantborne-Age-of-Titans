extends ShrineTab
## Shrine screen tab "Rest" (P05): restores health, stamina and essence (Shrine.rest), removes
## debuffs and keeps cooldowns running. Shows the pools before and after.

var _info: Label
var _pools: Label
var _result: Label
var rest_button: Button


func tab_title() -> String:
	return "Rest"


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_info = UiKit.label("Rest at the shrine: health, stamina and essence are restored and slows wear off. Cooldowns keep running.", 15, UiKit.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_pools = UiKit.label("", 16)
	add_child(_pools)
	rest_button = UiKit.button("Rest", 20)
	rest_button.pressed.connect(_on_rest)
	add_child(rest_button)
	_result = UiKit.label("", 15, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)


func first_focus() -> Control:
	return rest_button


func refresh() -> void:
	var p := player()
	if p == null or _pools == null:
		return
	var pools := p.entity.combatant.pools
	_pools.text = "Health %d / %d    Stamina %d / %d    Essence %d / %d" % [
		roundi(pools.health), roundi(pools.health_max), roundi(pools.stamina), roundi(pools.stamina_max),
		roundi(pools.essence), roundi(pools.essence_max)]
	var heals := bool(record().get("rest_heals", true))
	rest_button.disabled = not p.entity.is_alive()
	if not heals:
		_info.text = "This shrine offers shelter but no healing."


## The Rest button (also used by tests): Shrine.rest, then a summary line.
func press_rest() -> Dictionary:
	var s := shrine()
	var p := player()
	if s == null or p == null:
		return {"ok": false, "message": ""}
	var out := s.rest(p)
	_result.text = str(out.get("message", ""))
	_result.add_theme_color_override("font_color", UiKit.GOOD if out.ok else UiKit.WARN)
	screen.notify_changed()
	return out


func _on_rest() -> void:
	press_rest()


func result_text() -> String:
	return _result.text if _result != null else ""
