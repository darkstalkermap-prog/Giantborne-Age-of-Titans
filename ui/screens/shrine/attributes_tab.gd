extends ShrineTab
## Shrine screen tab "Attributes" (P12, plan §3.14 design 5): the AttributePanel (allocation with a
## derived preview, the ancestry line, talent points). Shown when the shrine record has attributes
## true and the giant has a progression component.

var panel_ui: AttributePanel


func tab_title() -> String:
	return "Attributes"


func available() -> bool:
	var p := player()
	return bool(record().get("attributes", true)) and p != null and p.progression != null


func _ready() -> void:
	panel_ui = AttributePanel.new()
	panel_ui.setup(player())
	add_child(panel_ui)


func first_focus() -> Control:
	return panel_ui.first_focus() if panel_ui != null else null


func refresh() -> void:
	if panel_ui != null:
		panel_ui.refresh()


## Plans and spends points through the panel (tests): {attribute: points} -> its confirm() result.
func spend(delta: Dictionary) -> Dictionary:
	panel_ui.reset()
	for key: Variant in delta:
		for i in int(delta[key]):
			panel_ui.add_point(str(key))
	var out := panel_ui.confirm()
	screen.notify_changed()
	return out
