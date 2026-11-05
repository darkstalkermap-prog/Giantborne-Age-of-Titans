extends HudWidget
## The player's active statuses as small chips above the resource panel ("SKIN 5s", "SLOW 2s",
## "MEND 3s", "SURGE 6s"): bottom-left, (16..340, -196..-170). Buffs are green, debuffs red;
## hidden statuses (tooling) never show. Reads StatusSet.hud_list; never changes anything.

const MAX_CHIPS := 6

var _row: HBoxContainer
var _chips: Array[PanelContainer] = []
var _labels: Array[Label] = []
var _text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.offset_left = 16
	_row.offset_right = 340
	_row.offset_top = -196
	_row.offset_bottom = -170
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for i in MAX_CHIPS:
		var chip := UiKit.panel(Color(0.05, 0.06, 0.08, 0.78))
		chip.visible = false
		var label := UiKit.label("", 12)
		chip.add_child(label)
		_row.add_child(chip)
		_chips.append(chip)
		_labels.append(label)


func _process(_delta: float) -> void:
	var rows := rows_for(player())
	var parts := PackedStringArray()
	for i in MAX_CHIPS:
		var visible_chip := i < rows.size()
		_chips[i].visible = visible_chip
		if not visible_chip:
			continue
		var row: Dictionary = rows[i]
		var text := chip_text(row)
		_labels[i].text = text
		_labels[i].add_theme_color_override("font_color", UiKit.BAD if row.debuff else UiKit.GOOD)
		parts.append(text)
	_text = "  ".join(parts)


## The statuses shown for `p` (StatusSet.hud_list: sorted by id, hidden ones left out).
static func rows_for(p: GiantPlayer) -> Array:
	if p == null or p.entity == null or p.entity.combatant == null:
		return []
	return p.entity.combatant.statuses.hud_list(Sim.tick)


## "SKIN 5s": the label and the whole seconds left (rounded up).
static func chip_text(row: Dictionary) -> String:
	return "%s %ds" % [row.get("label", "?"), ceili(float(row.get("remaining_s", 0.0)) - 1e-6)]


## What the row shows right now ("" when no status is active).
func visible_text() -> String:
	return _text


func layout_regions(view: Vector2) -> Dictionary:
	return {"status_row": anchored_rect(_row, view)}
