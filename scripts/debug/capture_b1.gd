class_name CaptureB1
extends CaptureQuarry
## B1: the armour's capture tour - --scenario=capture_b1 in the real world beside Stoneback's quarry, CaptureQuarry's
## staging (his AI off, each beat staged, a camera of its own, the giant kept alive), saving b1_NN_<moment>.png under
## --capture-dir=:
##   * the quarry folk's warning post on the quarry road's mouth, the giant passing it, its prompt (the HUD shown);
##   * the first lock on him, the plate hint (the HUD shown);
##   * each set worn by a stage-5 giant, mid-swing at him (the Iron, the Hide, the Quarry);
##   * the Quarry set's shoulders shown, then hidden (the giant's own look there; the numbers stay);
##   * his death, then the Quarry set and the Quarry Maul beside his body;
##   * a forge's Armour and Reforge tabs, the Character menu's Equipment tab with a piece's numbers before -> after.
## Staged as every tour is: the armour is put on by the rules (Armour, GameSession.expansion), the materials added.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --resolution 1280x720 -- --no-user-settings --mode=world --start=world.cp.millford --scenario=capture_b1 \
##     --skin --capture-dir=<out>

const SHOT_PREFIX_B1 := "b1"
const FORGE_SCENE := "res://scenes/world/forge.tscn"
const POST_SOUTH := Vector3(-447, 0, 515)

var _menu: UiScreen = null
var _forge: Forge = null


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_B1, n, moment]


func _hud(on: bool) -> void:
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = on


## Shows tutorial prompt `id` now (the one shown is put away): the tour reaches its moment faster than the game
## would let an earlier prompt end.
func _prompt(id: String) -> void:
	var td: Variant = Quests.get("tutorial")
	if td == null:
		notes.append("%s: no tutorial director" % id)
		return
	if not (td.current_prompt() as Dictionary).is_empty():
		td.dismiss("capture", Sim.tick)
	td.call("_show", GameData.get_record(id), Sim.tick)


func _wear(set_id: String) -> void:
	var eq := Armour.empty()
	for id: Variant in Armour.set_pieces(set_id):
		eq.pieces[str(id)] = {"tier": 1, "perk": ""}
		eq.slots[str(Armour.piece(str(id)).slot)] = str(id)
	GameSession.expansion.equipment = eq
	Armour.refresh_player(_p)


func _stack() -> ScreenStack:
	return _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack


func _close_menus() -> void:
	var st := _stack()
	if st != null:
		st.close_all()
	_menu = null


func _make_beats() -> Array:
	var swing_view := {"az": -62.0, "dist": 34.0, "h": 7.0, "look": 7.5, "on": "mid"}
	return [
		["road_warning", 5.0, func() -> void:
			_grow(3)
			_hud(true)
			_stage(_floor(-606, 456), _floor(-560, 476), _floor(-452, 522))
			_go(Vector3(-452, 0, 523))
			_face(_p, Vector3(-447, 8, 515))
			_prompt("tutorial.stoneback_warning_south"),
			{"at": Vector3(-425, 22, 545), "look": Vector3(-449, 10, 514), "fov": 55.0},
			[[4.0, "road_warning_post"]],
			func(t: float) -> void:
				if t < 3.0:
					_walk(Vector2(0, 0.35))],
		["plate_hint", 3.5, func() -> void:
			_grow(5)
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-582, 452))
			_p.targeting.try_lock()
			_prompt("tutorial.titan_plates"),
			{"az": -40.0, "dist": 44.0, "h": 8.0, "look": 9.0, "on": "mid"}, [[3.0, "plate_hint"]]],
		["iron_swing", 3.0, func() -> void:
			_hud(false)
			_p.targeting.release_lock("capture")
			_wear("armour_set.iron")
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-585, 455)),
			swing_view, [[func() -> bool: return _p.controller.action != null \
					and _p.controller.phase() == ActionDef.Phase.ACTIVE and _bt > 0.5, "iron_set_mid_swing"]],
			func(t: float) -> void:
				if t > 0.4 and t < 0.43:
					_swing()],
		["hide_swing", 3.0, func() -> void:
			_wear("armour_set.hide")
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-585, 455)),
			swing_view, [[func() -> bool: return _p.controller.action != null \
					and _p.controller.phase() == ActionDef.Phase.ACTIVE and _bt > 0.5, "hide_set_mid_swing"]],
			func(t: float) -> void:
				if t > 0.4 and t < 0.43:
					_swing()],
		["quarry_swing", 3.0, func() -> void:
			_wear("armour_set.quarry")
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-585, 455)),
			swing_view, [[func() -> bool: return _p.controller.action != null \
					and _p.controller.phase() == ActionDef.Phase.ACTIVE and _bt > 0.5, "quarry_set_mid_swing"]],
			func(t: float) -> void:
				if t > 0.4 and t < 0.43:
					_swing()],
		["shown_hidden", 3.0, func() -> void:
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-582, 470))
			_face(_p, _floor(-560, 480)),
			{"az": 0.0, "dist": 18.0, "h": 11.0, "look": 11.5, "on": "player"},
			[[1.0, "quarry_shoulders_shown"], [2.5, "quarry_shoulders_hidden"]],
			func(t: float) -> void:
				if t > 1.5 and t < 1.53:
					Armour.set_hidden(GameSession.expansion.equipment, "shoulders", true)
					Armour.refresh_player(_p)],
		["death", 6.0, func() -> void:
			Armour.set_hidden(GameSession.expansion.equipment, "shoulders", false)
			Armour.refresh_player(_p)
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-586, 456))
			_t.entity.combatant.pools.health = 40.0,
			CAM_NE, [[5.5, "stoneback_fallen"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("brow", 2000.0)],
		["by_his_body", 3.0, func() -> void:
			_p.equipment.grant_weapon("weapon.quarry_maul", true)
			_p.global_position = _floor(-578, 462)
			_face(_p, _floor(-560, 470)),
			{"at": Vector3(-548, 30, 496), "look": Vector3(-588, 14, 458), "fov": 50.0},
			[[2.5, "quarry_set_and_maul_by_his_body"]]],
		["forge", 4.5, func() -> void:
			_hud(true)
			WorldState.try_set_flag("world.quarry.reopened", true)
			for d: Array in [["item.stoneback_slab", 9], ["item.quarry_iron", 6], ["item.iron_ingot", 6],
					["item.hide", 6], ["item.titan_iron", 1], ["item.stoneback_heart_stone", 1]]:
				WorldState.add_item(str(d[0]), int(d[1]), "capture")
			GameSession.expansion.equipment = Armour.empty()
			for id: String in ["armour.quarry_pauldrons", "armour.quarry_greaves", "armour.iron_hauberk"]:
				Armour.grant(GameSession.expansion.equipment, id)
			Armour.set_tier(GameSession.expansion.equipment, "armour.quarry_greaves", 2)
			Armour.set_perk(GameSession.expansion.equipment, "armour.quarry_greaves", "armour_perk.steady")
			Armour.refresh_player(_p)
			_forge = (load(FORGE_SCENE) as PackedScene).instantiate() as Forge
			_forge.world_id = "capture.b1_forge"
			_forge.display_name = "Millford's quarry forge"
			_forge.works = PackedStringArray(["titan_stone"])
			_p.get_parent().add_child(_forge)
			_forge.global_position = _p.global_position + Vector3(6, 0, 0)
			var st := _stack()
			if st != null:
				_menu = st.open("forge", {"forge": _forge, "player": _p})
			if _menu is ForgeScreen:
				(_menu as ForgeScreen).show_tab(1)
				(_menu as ForgeScreen).select(1),
			{"at": Vector3(-548, 30, 496), "look": Vector3(-588, 14, 458), "fov": 50.0},
			[[1.2, "forge_armour_tab"], [3.2, "forge_reforge_tab"]],
			func(t: float) -> void:
				if t > 2.0 and t < 2.04 and _menu is ForgeScreen:
					(_menu as ForgeScreen).show_tab(2)
					(_menu as ForgeScreen).select(1)],
		["equipment_tab", 3.0, func() -> void:
			_close_menus()
			var st := _stack()
			if st != null:
				_menu = st.open("character", {"player": _p})
			if _menu is CharacterScreen:
				var cs := _menu as CharacterScreen
				cs.show_tab(CharacterScreen.TABS.find("Equipment"))
				cs._choose_slot("shoulders")
				if not cs.option_buttons.is_empty():
					cs.option_buttons[0].grab_focus(),
			{"at": Vector3(-548, 30, 496), "look": Vector3(-588, 14, 458), "fov": 50.0},
			[[2.0, "menu_equipment_compare"]]],
		["end", 0.5, func() -> void:
			_close_menus(),
			{"at": Vector3(-548, 30, 496), "look": Vector3(-588, 14, 458), "fov": 50.0}, []],
	]
