extends ShrineTab
## Shrine screen tab "Attributes" (P12, plan §3.14 design 5): the AttributePanel (allocation with a
## derived preview, the ancestry line, talent points). Shown when the shrine record has attributes
## true and the giant has a progression component.
##
## P16: the panel's rows ([-, +] per attribute, then Confirm and Reset) are the tab's focus rows;
## whenever the panel refreshes (a planned point can disable a + or a - button) the screen rewires
## them.

var panel_ui: AttributePanel


func tab_title() -> String:
	return "Attributes"


func available() -> bool:
	var p := player()
	return bool(record().get("attributes", true)) and p != null and p.progression != null


func _ready() -> void:
	panel_ui = AttributePanel.new()
	panel_ui.setup(player())
	panel_ui.allocated.connect(_on_allocated)
	panel_ui.refreshed.connect(_on_panel_refreshed)
	add_child(panel_ui)


## Spent points change the maxima: the screen's header and the other tabs refresh.
func _on_allocated(_result: Dictionary) -> void:
	if screen != null:
		screen.notify_changed()


## The panel changed which buttons work: rewire the focus while this tab is shown.
func _on_panel_refreshed() -> void:
	if screen != null and is_instance_valid(screen) and screen.is_inside_tree() and is_visible_in_tree():
		screen.refresh_focus()


func first_focus() -> Control:
	return panel_ui.first_focus() if panel_ui != null else null


func focus_rows() -> Array:
	return panel_ui.focus_rows() if panel_ui != null else []


func refresh() -> void:
	if panel_ui != null:
		panel_ui.refresh()


## Plans and spends points through the panel (tests): {attribute: points} -> its confirm() result.
func spend(delta: Dictionary) -> Dictionary:
	panel_ui.reset()
	for key: Variant in delta:
		for i in int(delta[key]):
			panel_ui.add_point(str(key))
	return panel_ui.confirm()
