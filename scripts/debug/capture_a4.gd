class_name CaptureA4
extends CaptureTitan
## A4: the capture tour of the topple and the Character menu - --scenario=capture_a4 on the quarry test arena, with
## CaptureTitan's machinery (his AI off, each beat staged, a camera of its own, the giant kept alive, the plates broken
## through the ordinary resolution), saving a4_NN_<moment>.png:
##   * a stage-5 giant's heavy blow on his left shin breaks the plate and drops him to a knee (low, from his side);
##   * on his knee, the giant behind him strikes his lowered back (from the side);
##   * the Character menu over the arena, one still a tab (Giant, Attributes, Equipment, Titans, Materials) - the
##     session's titan record and inventory as this tour left them (Stoneback sighted, his plates broken; the
##     materials his loot table gives, added for the Materials tab: staged, as the rest of the tour is).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --resolution 1280x720 -- --no-user-settings --level=res://scenes/test/quarry_test.tscn \
##     --scenario=capture_a4 --skin --capture-dir=<out>

const SHOT_PREFIX_A4 := "a4"

var _screen: CharacterScreen = null


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_A4, n, moment]


func _make_beats() -> Array:
	var kneel_side := {"az": 108.0, "dist": 30.0, "h": 4.5, "look": 7.0, "on": "mid"}
	return [
		["shin_break", 3.4, func() -> void:
			# (he faces +Z; the giant at his left, before his left shin)
			_stage(Vector3(0, 0.05, -20), Vector3(0, 0, 20), Vector3(7.5, 0.05, -11.5))
			_face(_p, Vector3(1.9, 0.0, -18.7)),
			{"az": -24.0, "dist": 40.0, "h": 2.4, "look": 7.0, "on": "mid"},
			[[1.1, "shin_plate_breaks"], [2.7, "down_on_a_knee", {"az": 48.0, "dist": 40.0, "h": 3.0, "look": 7.0,
				"on": "titan"}]],
			func(t: float) -> void:
				if t > 0.62 and t < 0.65:
					_swing()
				if t > 1.0 and t < 1.03 and not _t.plates().is_broken("shin_l"):
					_blow("shin_l", 3000.0)],
		["back_strike", 3.2, func() -> void:
			var fwd := Vector3(-sin(_t.facing_yaw), 0.0, -cos(_t.facing_yaw))
			var behind := _t.global_position - fwd * 9.0
			_p.global_position = Vector3(behind.x, 0.05, behind.z)
			_face(_p, _t.global_position)
			if not _t.plates().is_broken("back"):
				_blow("back", 3000.0),
			kneel_side, [[func() -> bool: return _p.controller.action != null \
					and _p.controller.phase() == ActionDef.Phase.ACTIVE and _bt > 0.9, "kneeling_back_struck"]],
			func(t: float) -> void:
				if t > 0.8 and t < 0.83:
					_swing()],
		["character_menu", 5.6, func() -> void:
			_open_menu(),
			{"az": 30.0, "dist": 46.0, "h": 9.0, "look": 9.0, "on": "titan"},
			[[0.5, "menu_giant"], [1.5, "menu_attributes"], [2.5, "menu_equipment"], [3.5, "menu_titans"],
				[4.5, "menu_materials"]],
			func(t: float) -> void:
				if _screen == null or not is_instance_valid(_screen):
					return
				var tab := clampi(int(floor(t)), 0, CharacterScreen.TABS.size() - 1)
				if _screen.current_tab() != str(CharacterScreen.TABS[tab]):
					_screen.show_tab(tab)],
	]


## The menu over the arena: main's layer shown again (CaptureTitan hid it for the fight's stills; the HUD hides
## itself under a screen), the session's titan record as the tour left it, his loot's materials held.
func _open_menu() -> void:
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = true
	ExpansionState.note_sighted(GameSession.expansion, "titan.stoneback", 64.0, 0)
	ExpansionState.note_plates(GameSession.expansion, "titan.stoneback", _t.plates().broken_count())
	for d: Dictionary in ExpansionState.loot_of("loot.stoneback"):
		WorldState.add_item(str(d.item), int(d.count), "capture")
	WorldState.add_item("item.iron_ingot", 3, "capture")
	var stack := _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack
	if stack != null:
		_screen = stack.open("character", {"player": _p}) as CharacterScreen
	if _screen == null:
		notes.append("character_menu: the Character menu did not open")
