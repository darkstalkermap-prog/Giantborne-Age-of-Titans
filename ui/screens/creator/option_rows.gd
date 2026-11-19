class_name OptionRows
extends RefCounted
## The creator's categories and their rows (P44; plan M10 §2.10): what each category shows, the row widgets
## and the record paths they read and write. CreatorScreen builds a category's rows with build_rows() and
## turns every pick into a new record with with_value() / with_scar(); nothing here touches a node outside
## the rows it makes, the preview or the simulation.
##
## Row kinds (the P16 focus rules: a row is one line of focusable controls, up / down between rows):
##   * swatch  - a row of colour buttons, every one named; moving the focus onto a swatch applies it at once
##               (moving previews and keeps, like the cyclers), A or a click too. The focus that enters the
##               row with the keyboard or the pad lands on the chosen swatch; a mouse press stays on the
##               swatch it pressed and applies it (M10 gate, LA-2). A locked swatch takes the
##               focus but applies nothing: the line under the row says why ("Choose your line at a shrine of
##               the Old Kingdom").
##   * cycler  - one focusable button "<  Long, combed back  >": left / right (D-pad, arrows) step through the
##               choices and apply each at once; A or a click steps forward, a click on its left third back.
##               Its own left and right are consumed, so the focus never leaves it sideways.
##   * slider  - an HSlider (the greys): left / right move it; the changes of one slider in a row are one step
##               of the undo history.
##   * toggle  - a CheckButton (scars): A or a click turns it on or off.
##   * preset  - a button per preset: A or a click puts the whole preset on. The focused preset's description
##               shows in one place under the list (CreatorScreen's), so that no button moves when the focus
##               does: a mouse press moves the focus, and a button that jumps under the pointer between the
##               press and the release loses the click (M10 gate, LA-1).
## Every design row (tattoos, war paint, scars, the ancestry mark) has a note line that says "Hidden by your
## clothing" while the current outfit covers its region (Appearance.covered_regions with the giant's index).
##
## P53 (plan M11 §2.5): the record is version 2 (clothing by slot), and today's rows keep working on it - the
## smallest change until the creator II (P55): the Outfit row still shows the six outfits and puts one on by
## filling its slots (Appearance.with_outfit), the two dye rows edit the outfit's cloth and leather dyes
## (outfit.dyes.cloth, outfit.dyes.leather), and the one War paint row puts one paint on in its place (face or
## body) and takes the other off (Appearance.with_paint). The record paths M10's rows used ("outfit.primary",
## "outfit.secondary", "paint.design") still read and write the same values (LEGACY_KEYS), for the sheets and
## the probes that name them.

## The creator's categories, in tab order.
const CATEGORIES := ["Presets", "Skin", "Eyes", "Hair", "Beard", "Tattoos", "War paint", "Scars", "Clothing"]
## The scope of Appearance.random_record for each category (Y / R randomizes the open one).
const RANDOM_SCOPE := {"Presets": "presets", "Skin": "skin", "Eyes": "eyes", "Hair": "hair", "Beard": "beard",
	"Tattoos": "tattoos", "War paint": "paint", "Scars": "scars", "Clothing": "outfit"}
## The note of a design row whose region the outfit covers (plan M10 §2.10, decision 18).
const HIDDEN_NOTE := "Hidden by your clothing"
## The beard colour that follows the hair's ("" in the record).
const SAME_AS_HAIR := "Same as hair"
const MARK_SHOWN := "Shown"
const MARK_HIDDEN := "Hidden"
## Under the mark row before a line is chosen.
const MARK_NO_LINE := "Your line's mark shows here once you choose your line at a shrine of the Old Kingdom."
const SWATCH_PX := 34
const NOTE_COLOR := Color(1.0, 0.72, 0.35)
## The record paths of the design regions' tattoo rows.
const TATTOO_ROWS := {"tattoos.arms": "arms", "tattoos.chest": "chest", "tattoos.back": "back", "tattoos.face": "face"}
## M10's record paths of the dye rows and the record v2's paths they edit now (P53).
const LEGACY_KEYS := {"outfit.primary": "outfit.dyes.cloth", "outfit.secondary": "outfit.dyes.leather"}
## The one War paint row's path (its value is the record's first paint: Appearance.first_paint).
const PAINT_ROW := "paint.design"


# --------------------------------------------------------------------------- the categories

## The row specs of a category: [{key, kind, label, set?, region?, id?, description?}], top to bottom.
## `key` is the record path the row edits ("hair.color", "tattoos.back", "scar.brow", "preset.<id>").
static func row_specs(category: String) -> Array:
	match category:
		"Presets":
			var out: Array = []
			for id: String in Appearance.preset_ids():
				var rec := GameData.get_record(id)
				out.append({"key": "preset." + id, "kind": "preset", "label": str(rec.get("display_name", id)),
					"id": id, "description": str(rec.get("description", ""))})
			return out
		"Skin":
			return [{"key": "skin", "kind": "swatch", "set": "skin", "label": "Skin tone"}]
		"Eyes":
			return [{"key": "eyes", "kind": "swatch", "set": "eyes", "label": "Eye colour"}]
		"Hair":
			return [{"key": "hair.style", "kind": "cycler", "set": "hair", "label": "Style"},
				{"key": "hair.color", "kind": "swatch", "set": "haircolor", "label": "Colour"},
				{"key": "hair.grey", "kind": "slider", "label": "Grey"}]
		"Beard":
			return [{"key": "beard.style", "kind": "cycler", "set": "beard", "label": "Style"},
				{"key": "beard.color", "kind": "swatch", "set": "haircolor", "label": "Colour"},
				{"key": "beard.grey", "kind": "slider", "label": "Grey"}]
		"Tattoos":
			var out: Array = []
			for key: String in TATTOO_ROWS:
				out.append({"key": key, "kind": "cycler", "set": "tattoo", "region": TATTOO_ROWS[key],
					"label": str(TATTOO_ROWS[key]).capitalize()})
			out.append({"key": "tattoos.ink", "kind": "swatch", "set": "ink", "label": "Ink"})
			out.append({"key": "mark", "kind": "cycler", "set": "mark", "label": "Ancestry mark"})
			return out
		"War paint":
			return [{"key": "paint.design", "kind": "cycler", "set": "paint", "label": "Design"},
				{"key": "paint.color", "kind": "swatch", "set": "paintcolor", "label": "Colour"}]
		"Scars":
			var out: Array = []
			for id: String in Appearance.option_ids("scar"):
				out.append({"key": "scar." + id.get_slice(".", 1), "kind": "toggle", "set": "scar", "id": id,
					"label": str(Appearance.option(id).get("name", id))})
			return out
		"Clothing":
			return [{"key": "outfit.set", "kind": "cycler", "set": "outfit", "label": "Outfit"},
				{"key": "outfit.dyes.cloth", "kind": "swatch", "set": "dye", "label": "Main dye"},
				{"key": "outfit.dyes.leather", "kind": "swatch", "set": "dye", "label": "Second dye"}]
	return []


## The choices of a swatch or cycler row for a giant of `ancestry_id`: [{id, name, color, locked, reason}] in
## data order. Design cyclers start with "None" (""), the beard's colour with "Same as hair" (""), the mark
## row is Shown ("auto") / Hidden ("none").
static func choices(spec: Dictionary, ancestry_id: String) -> Array:
	var out: Array = []
	var key := str(spec.get("key", ""))
	match key:
		"mark":
			return [{"id": Appearance.MARK_AUTO, "name": MARK_SHOWN, "locked": false, "reason": ""},
				{"id": Appearance.MARK_NONE, "name": MARK_HIDDEN, "locked": false, "reason": ""}]
		"beard.color":
			out.append({"id": "", "name": SAME_AS_HAIR, "locked": false, "reason": "", "same": true})
	if str(spec.get("set", "")) in ["tattoo", "paint"]:
		out.append({"id": "", "name": "None", "locked": false, "reason": ""})
	var region := str(spec.get("region", ""))
	for o: Dictionary in Appearance.options(str(spec.get("set", "")), ancestry_id):
		if region != "" and str(o.get("region", "")) != region:
			continue
		var c := {"id": str(o.id), "name": str(o.get("name", o.id)), "locked": bool(o.locked), "reason": str(o.reason)}
		if str(o.get("color", "")) != "" and Color.html_is_valid(str(o.color)):
			c["color"] = Color.html(str(o.color))
			if str(spec.get("set", "")) == "skin":
				c["color"] = GiantLook.drawn_tone(o)   # P51: the colour the skin draws at, not the record's
		out.append(c)
	return out


# --------------------------------------------------------------------------- the record paths

## The value a row shows from `record` (an option id, a grey, "auto"/"none", or a bool for a scar toggle).
static func value_of(record: Dictionary, key: String) -> Variant:
	if key.begins_with("scar."):
		var scars: Variant = record.get("scars", [])
		return typeof(scars) == TYPE_ARRAY and (scars as Array).has("scar." + key.get_slice(".", 1))
	if key.begins_with("preset."):
		return str(record.get("preset", "")) == key.substr(7)
	if key == PAINT_ROW:
		return Appearance.first_paint(record)
	var parts := str(LEGACY_KEYS.get(key, key)).split(".")
	var v: Variant = record
	for p: String in parts:
		if typeof(v) != TYPE_DICTIONARY:
			return ""
		v = (v as Dictionary).get(p, "")
	return v


## A copy of `record` with the row `key` set to `value`; any manual edit makes the look "custom" (its preset
## is cleared: the summary and SKIN_STATS read it). A preset row puts that preset's whole record on.
static func with_value(record: Dictionary, key: String, value: Variant) -> Dictionary:
	if key.begins_with("preset."):
		var rec := Appearance.preset_record(key.substr(7))
		return rec if not rec.is_empty() else record.duplicate(true)
	var out: Dictionary
	if key == "outfit.set":
		out = Appearance.with_outfit(record, str(value))
	elif key == PAINT_ROW:
		out = Appearance.with_paint(record, str(value))
	else:
		out = record.duplicate(true)
		_set_path(out, str(LEGACY_KEYS.get(key, key)).split("."), value)
	out["preset"] = ""
	return out


## Sets `value` at the record path `parts` inside `d` (the blocks on the way copied or made).
static func _set_path(d: Dictionary, parts: PackedStringArray, value: Variant) -> void:
	if parts.size() == 1:
		d[parts[0]] = value
		return
	var block: Dictionary = (d.get(parts[0]) as Dictionary).duplicate(true) if typeof(d.get(parts[0])) == TYPE_DICTIONARY else {}
	_set_path(block, parts.slice(1), value)
	d[parts[0]] = block


## A copy of `record` with the scar `scar_id` on or off (at most Appearance.MAX_SCARS: a fifth is refused and
## the record comes back as it was).
static func with_scar(record: Dictionary, scar_id: String, on: bool) -> Dictionary:
	var out := record.duplicate(true)
	var scars: Array = (out.get("scars") as Array).duplicate() if typeof(out.get("scars")) == TYPE_ARRAY else []
	if on and not scars.has(scar_id):
		if scars.size() >= Appearance.MAX_SCARS:
			return record.duplicate(true)
		scars.append(scar_id)
	elif not on:
		scars.erase(scar_id)
	out["scars"] = scars
	out["preset"] = ""
	return out


## True when two records describe the same look (numbers compared as numbers, so a grey read back from JSON
## as a float equals the slider's).
static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k: Variant in da:
			if not db.has(k) or not same(da[k], db[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not same(a[i], b[i]):
				return false
		return true
	var na := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var nb := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if na and nb:
		return absf(float(a) - float(b)) < 1e-6
	return typeof(a) == typeof(b) and a == b


# --------------------------------------------------------------------------- what a row shows and covers

## The design region a design row shows ("face", "chest", "back", "arms", "hand_l", or "" for a row that is not
## about a place on the body): a tattoo row's region, the war paint's and a scar's by their design, the
## mark's by the line's mark. The preview frames it while the row has the focus.
static func row_region(spec: Dictionary, record: Dictionary, index: Dictionary, ancestry_id: String) -> String:
	var key := str(spec.get("key", ""))
	if TATTOO_ROWS.has(key):
		return str(TATTOO_ROWS[key])
	match key:
		"paint.design", "paint.color":
			var o := Appearance.option(str(value_of(record, "paint.design")))
			return str(o.get("region", "face")) if not o.is_empty() else "face"
		"mark":
			var m := Appearance.ancestry_mark(ancestry_id)
			return _design_region(str(m.get("design", "")), index) if not m.is_empty() else "arms"
		"tattoos.ink":
			for k: String in TATTOO_ROWS:
				if str(value_of(record, k)) != "":
					return str(TATTOO_ROWS[k])
			return "arms"
	if key.begins_with("scar."):
		return _design_region(str(Appearance.option(str(spec.get("id", ""))).get("design", "")), index)
	return ""


## The design region of a design id by its first body region in the index (the hand for region 10).
static func _design_region(design_id: String, index: Dictionary) -> String:
	var d: Variant = (index.get("designs", {}) as Dictionary).get(design_id) if typeof(index.get("designs")) == TYPE_DICTIONARY else null
	var regions: Array = (d as Dictionary).get("regions", []) if typeof(d) == TYPE_DICTIONARY else []
	if regions.is_empty():
		return "face"
	var first := int(regions[0])
	if first == 10:
		return "hand_l"   # the floor's one hand design, the knuckles scar, is on the left hand (tools/giant/kit)
	for region: String in Appearance.DESIGN_REGION_BODY:
		if (Appearance.DESIGN_REGION_BODY[region] as Array).has(first):
			return region
	return "face"


## What the outfit of `record` covers, for row_hidden(): {"regions": the design regions
## (Appearance.covered_regions), "body": the body region ids where a design is hidden
## (Appearance.design_hidden_body_regions)}. Computed once per record.
static func coverage(record: Dictionary, index: Dictionary, ancestry_id: String) -> Dictionary:
	var garments: Array = Appearance.record_garments(Appearance.sanitize(record, ancestry_id, false).record)
	return {"regions": Appearance.covered_regions(record, index, ancestry_id),
		"body": Appearance.design_hidden_body_regions(garments, index)}


## True when the outfit of `record` hides the design a row shows (its note reads HIDDEN_NOTE). A tattoo or
## war paint row by its design region (Appearance.covered_regions); a scar or the mark by every body region of
## its design (Appearance.design_hidden_body_regions); with no design chosen, by the row's own region.
## `cover` is coverage() of the record (computed here when empty).
static func row_hidden(spec: Dictionary, record: Dictionary, index: Dictionary, ancestry_id: String,
		cover: Dictionary = {}) -> bool:
	var key := str(spec.get("key", ""))
	if cover.is_empty():
		cover = coverage(record, index, ancestry_id)
	var covered: PackedStringArray = cover.regions
	if TATTOO_ROWS.has(key):
		return covered.has(str(TATTOO_ROWS[key]))
	if key == "paint.design":
		var o := Appearance.option(str(value_of(record, "paint.design")))
		return not o.is_empty() and covered.has(str(o.get("region", "")))
	var design := ""
	if key.begins_with("scar."):
		design = str(Appearance.option(str(spec.get("id", ""))).get("design", ""))
	elif key == "mark":
		design = str(Appearance.ancestry_mark(ancestry_id).get("design", ""))
	if design == "" or typeof(index.get("designs")) != TYPE_DICTIONARY:
		return false
	var d: Variant = (index.designs as Dictionary).get(design)
	var regions: Array = (d as Dictionary).get("regions", []) if typeof(d) == TYPE_DICTIONARY else []
	if regions.is_empty():
		return false
	var hidden: PackedInt32Array = cover.body
	for r: Variant in regions:
		if not hidden.has(int(r)):
			return false
	return true


# --------------------------------------------------------------------------- building

## The rows of `category`, built (not yet in the tree): Array of OptionRows.Row.
static func build_rows(category: String, ancestry_id: String) -> Array:
	var out: Array = []
	for spec: Dictionary in row_specs(category):
		match str(spec.kind):
			"swatch":
				out.append(SwatchRow.new(spec, choices(spec, ancestry_id)))
			"cycler":
				out.append(CyclerRow.new(spec, choices(spec, ancestry_id)))
			"slider":
				out.append(SliderRow.new(spec))
			"toggle":
				out.append(ToggleRow.new(spec))
			"preset":
				out.append(PresetRow.new(spec))
	return out


## A row's frame: a label (its name) above its controls and a note line under them.
class Row extends VBoxContainer:
	## The user picked a value (an option id, a grey, a bool): CreatorScreen makes the new record.
	signal picked(row: Row, value: Variant)
	## A control of the row took the focus (the preview frames the row's region).
	signal focused(row: Row)

	var spec: Dictionary = {}
	var key := ""
	var title: Label
	var note: Label
	var _note_base := ""

	func _init(p_spec: Dictionary) -> void:
		spec = p_spec
		key = str(p_spec.get("key", ""))
		name = key.replace(".", "_")
		add_theme_constant_override("separation", 3)
		title = UiKit.label(str(p_spec.get("label", key)), 15, UiKit.MUTED)
		add_child(title)

	## The row's focusable controls, left to right (one focus row).
	func focus_controls() -> Array:
		return []

	## The control the focus lands on when the row is entered (the current value's).
	func main_control() -> Control:
		var c := focus_controls()
		return c[0] if not c.is_empty() else null

	## Shows `value` (from the record) without emitting anything.
	func show_value(_value: Variant) -> void:
		pass

	## The note line under the row ("" hides it): "Hidden by your clothing", a locked option's reason.
	func set_note(text: String) -> void:
		_note_base = text
		_show_note(text)

	func note_text() -> String:
		return note.text if note != null and note.visible else ""

	func _show_note(text: String) -> void:
		if note == null:
			note = UiKit.label("", 13, OptionRows.NOTE_COLOR)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(note)
		note.text = text
		note.visible = text != ""

	func _wire_focus(c: Control) -> void:
		c.focus_entered.connect(func() -> void: focused.emit(self))


## A row of named colour swatches (skin, eyes, hair and beard colours, inks, paint colours, dyes).
class SwatchRow extends Row:
	var buttons: Dictionary = {}     ## option id ("" for "Same as hair") -> Button
	var choices: Array = []
	var name_label: Label
	var selected := ""
	var _box: HFlowContainer
	var _inside := false     ## the focus is on one of this row's swatches

	func _init(p_spec: Dictionary, p_choices: Array) -> void:
		super(p_spec)
		choices = p_choices
		_box = HFlowContainer.new()
		_box.add_theme_constant_override("h_separation", 6)
		_box.add_theme_constant_override("v_separation", 6)
		add_child(_box)
		for c: Dictionary in choices:
			var b := Button.new()
			b.name = "Swatch_" + (str(c.id).get_slice(".", 1) if str(c.id) != "" else "same")
			b.custom_minimum_size = Vector2(OptionRows.SWATCH_PX, OptionRows.SWATCH_PX)
			b.focus_mode = Control.FOCUS_ALL
			b.tooltip_text = str(c.name) + (" (%s)" % c.reason if bool(c.locked) else "")
			var col: Color = c.get("color", Color(0.5, 0.5, 0.5))
			if bool(c.get("same", false)):
				b.text = "="
				b.add_theme_font_size_override("font_size", 16)
			if bool(c.locked):
				b.text = "x"
				b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
			b.set_meta("swatch_color", col)
			_box.add_child(b)
			buttons[str(c.id)] = b
			var id := str(c.id)
			b.focus_entered.connect(_on_swatch_focus.bind(id))
			b.focus_exited.connect(_on_swatch_unfocus)
			b.pressed.connect(_on_swatch_pressed.bind(id))
			_wire_focus(b)
		name_label = UiKit.label("", 14, UiKit.TEXT)
		add_child(name_label)
		_style_all()

	func focus_controls() -> Array:
		var out: Array = []
		for c: Dictionary in choices:
			out.append(buttons[str(c.id)])
		return out

	func main_control() -> Control:
		return buttons.get(selected, focus_controls()[0] if not choices.is_empty() else null)

	func show_value(value: Variant) -> void:
		selected = str(value)
		_style_all()
		_name_of(selected)

	## The choice of an id ({} when unknown).
	func choice(id: String) -> Dictionary:
		for c: Dictionary in choices:
			if str(c.id) == id:
				return c
		return {}

	## Moving along the row applies each swatch; entering the row from another (up, down, Tab) lands on the
	## selected swatch and changes nothing. A mouse press gives the swatch under the pointer the focus before
	## its own press: it keeps the focus and is applied at once (sending the focus to the selected swatch
	## while the button is held would make the pressed swatch drop its click).
	func _on_swatch_focus(id: String) -> void:
		if not _inside:
			_inside = true
			if id != selected and buttons.has(selected) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_redirect.call_deferred()
				return
		_pick(id)

	func _redirect() -> void:
		var b: Button = buttons.get(selected)
		if b != null and is_instance_valid(b) and UiNav.focusable(b):
			b.grab_focus()

	func _on_swatch_unfocus() -> void:
		_check_inside.call_deferred()

	func _check_inside() -> void:
		if not is_inside_tree():
			_inside = false
			return
		var owner := get_viewport().gui_get_focus_owner()
		_inside = owner != null and owner.get_parent() == _box

	func _on_swatch_pressed(id: String) -> void:
		_pick(id)

	func _pick(id: String) -> void:
		var c := choice(id)
		if c.is_empty():
			return
		if bool(c.locked):
			name_label.text = "%s: %s" % [c.name, c.reason]
			name_label.add_theme_color_override("font_color", OptionRows.NOTE_COLOR)
			return
		if id != selected:
			picked.emit(self, id)
		else:
			_name_of(id)

	func _name_of(id: String) -> void:
		var c := choice(id)
		name_label.text = str(c.get("name", ""))
		name_label.add_theme_color_override("font_color", UiKit.TEXT)

	func _style_all() -> void:
		for id: Variant in buttons:
			var b: Button = buttons[id]
			var on := str(id) == selected
			if b.has_meta("selected") and bool(b.get_meta("selected")) == on:
				continue
			var col: Color = b.get_meta("swatch_color", Color(0.5, 0.5, 0.5))
			for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				b.add_theme_stylebox_override(st, OptionRows.swatch_box(col, on, st == "hover"))
			b.add_theme_stylebox_override("focus", OptionRows.focus_box())
			b.set_meta("selected", on)


## One control stepping through choices: "<  Long, combed back  >".
class CyclerRow extends Row:
	var button: Button
	var choices: Array = []
	var index := 0

	func _init(p_spec: Dictionary, p_choices: Array) -> void:
		super(p_spec)
		choices = p_choices
		button = Button.new()
		button.name = "Cycler"
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(300, 34)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.add_theme_font_size_override("font_size", 16)
		button.gui_input.connect(_on_gui_input)
		button.pressed.connect(_on_pressed)
		add_child(button)
		_wire_focus(button)
		_show()

	func focus_controls() -> Array:
		return [button]

	func show_value(value: Variant) -> void:
		for i in choices.size():
			if str(choices[i].id) == str(value):
				index = i
		_show()

	func value() -> String:
		return str(choices[index].id) if index < choices.size() else ""

	## Steps `dir` (+1 or -1) to the next choice that is not locked, applies it and returns its id.
	func step(dir: int) -> String:
		if choices.is_empty():
			return ""
		var i := index
		for n in choices.size():
			i = (i + dir + choices.size()) % choices.size()
			if not bool(choices[i].locked):
				break
		if i != index:
			index = i
			_show()
			picked.emit(self, value())
		return value()

	func _show() -> void:
		var label := str(choices[index].name) if index < choices.size() else ""
		button.text = "<   %s   >" % label

	func _on_gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true):
			step(-1)
			button.accept_event()
		elif event.is_action_pressed("ui_right", true):
			step(1)
			button.accept_event()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			# a click on the left third steps back (the right two thirds: the button's own pressed, forward)
			if (event as InputEventMouseButton).position.x < button.size.x / 3.0:
				step(-1)
				button.accept_event()

	func _on_pressed() -> void:
		step(1)


## A slider (the greys).
class SliderRow extends Row:
	var slider: HSlider
	var value_label: Label
	var _quiet := false

	func _init(p_spec: Dictionary) -> void:
		super(p_spec)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		add_child(h)
		slider = HSlider.new()
		slider.name = "Slider"
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(300, 28)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_on_changed)
		h.add_child(slider)
		value_label = UiKit.label("", 14)
		h.add_child(value_label)
		_wire_focus(slider)

	func focus_controls() -> Array:
		return [slider]

	func show_value(value: Variant) -> void:
		_quiet = true
		slider.value = float(value)
		_quiet = false
		_label(float(value))

	func _on_changed(v: float) -> void:
		_label(v)
		if not _quiet:
			picked.emit(self, snappedf(v, 0.01))

	func _label(v: float) -> void:
		var words := Appearance.grey_words(v)
		value_label.text = words.capitalize() if words != "" else "None"


## An on / off option (a scar).
class ToggleRow extends Row:
	var check: CheckButton
	var _quiet := false

	func _init(p_spec: Dictionary) -> void:
		super(p_spec)
		title.visible = false
		check = CheckButton.new()
		check.name = "Toggle"
		check.text = str(p_spec.get("label", ""))
		check.focus_mode = Control.FOCUS_ALL
		check.add_theme_font_size_override("font_size", 16)
		check.toggled.connect(_on_toggled)
		add_child(check)
		_wire_focus(check)

	func focus_controls() -> Array:
		return [check]

	func show_value(value: Variant) -> void:
		_quiet = true
		check.button_pressed = bool(value)
		_quiet = false

	func _on_toggled(on: bool) -> void:
		if not _quiet:
			picked.emit(self, on)


## A preset: its name as a button. Its description is shown by the screen, in one place under the list, while
## the preset has the focus (a description that opened under the focused button moved every button below it).
class PresetRow extends Row:
	var button: Button
	var description := ""

	func _init(p_spec: Dictionary) -> void:
		super(p_spec)
		title.visible = false
		description = str(p_spec.get("description", ""))
		button = Button.new()
		button.name = "Preset"
		button.text = str(p_spec.get("label", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(func() -> void: picked.emit(self, true))
		add_child(button)
		_wire_focus(button)

	func focus_controls() -> Array:
		return [button]

	func show_value(value: Variant) -> void:
		button.add_theme_color_override("font_color", UiKit.GOOD if bool(value) else UiKit.TEXT)


# --------------------------------------------------------------------------- styles

static var _boxes := {}


## A swatch's box: its colour, a light border when selected (shared: one per colour and state).
static func swatch_box(col: Color, selected: bool, hover: bool) -> StyleBoxFlat:
	var key := [col.to_rgba32(), selected, hover]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	_boxes[key] = sb
	sb.bg_color = col.lightened(0.08) if hover else col
	sb.set_corner_radius_all(4)
	sb.border_color = Color(1.0, 0.86, 0.5) if selected else Color(0, 0, 0, 0.6)
	sb.set_border_width_all(3 if selected else 1)
	return sb


## The focus outline drawn over a swatch (the theme's is thin on a coloured box; shared).
static func focus_box() -> StyleBoxFlat:
	if _boxes.has("focus"):
		return _boxes.focus
	var sb := StyleBoxFlat.new()
	_boxes["focus"] = sb
	sb.draw_center = false
	sb.border_color = Color(1, 1, 1, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.expand_margin_left = 3
	sb.expand_margin_right = 3
	sb.expand_margin_top = 3
	sb.expand_margin_bottom = 3
	return sb
