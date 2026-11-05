extends IntegrationSuite
## Weapons with fit stages and equipment (plan §3.8, decision 3): the shipped weapons and
## movesets; equipping is refused mid-swing and the tree below stage 3; the weapon mesh is as long
## as the sweep at stages 1-3 and the swing reaches as far as it should; an unreforged sword at
## stage 3 keeps its stage-2 length, the HUD warns, and its heavy still lands on a soldier at the
## giant's feet, while the reforged blade scales to stage 3; the sword's first light grants 4
## fury; the equipment's save keys round-trip silently; and in first person at stage 3 the sword,
## the hammer and the tree never cover the crosshair for more than 30 ticks in a row during a
## light chain.

const WEAPONS := ["weapon.club", "weapon.sword", "weapon.hammer"]
const MAX_OBSCURED_TICKS := 30

var equipped: Array[String] = []
var loadout_events := 0
var messages: Array[String] = []


func before_each() -> void:
	await super()
	equipped.clear()
	loadout_events = 0
	messages.clear()
	Events.weapon_equipped.connect(_on_equipped)
	Events.loadout_changed.connect(_on_loadout)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for sig: Signal in [Events.weapon_equipped, Events.loadout_changed, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_equipped(_t: int, _id: String, weapon_id: String) -> void:
	equipped.append(weapon_id)


func _on_loadout(_t: int, _id: String) -> void:
	loadout_events += 1


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


## A giant standing on the floor (growth and equipping need LOCOMOTION on the ground).
func _grounded_player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _equip(p: GiantPlayer, id: String) -> Dictionary:
	return p.equipment.grant_weapon(id, true)


func _grow(p: GiantPlayer, stage: int) -> void:
	if p.growth_stage != stage:
		var r: Dictionary = p.growth.debug_set_stage(stage)
		assert_true(r.ok, "grew to stage %d (%s)" % [stage, r.reason])
	await step_ticks(2)


func _landed(target_id: String, attack_id: String) -> int:
	var n := 0
	for r in hits_on(target_id):
		if r.event.action_id == attack_id:
			n += 1
	return n


## Starts `attack_id` on its own, waits for its active phase to end, and returns how many of its
## hits landed on `target_id`.
func _swing(p: GiantPlayer, attack_id: String, target_id: String) -> int:
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	var a := GameData.get_action(attack_id)
	assert_eq(p.controller.request(&"attack", {"action_id": attack_id}), CombatController.Verdict.ACCEPT,
		"%s starts" % attack_id)
	await step_ticks(a.windup_ticks + a.active_ticks + 2)
	var n := _landed(target_id, attack_id)
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
	await step_ticks(1)
	return n


# --------------------------------------------------------------------------- data

func test_shipped_weapons_fit_stages_and_movesets() -> void:
	for id: String in WEAPONS:
		var rec := GameData.get_record(id)
		assert_eq(int(rec.get("fit_max_stage", 10)), 2, "%s fits up to stage 2" % id)
		assert_true(bool(rec.get("scales_with_growth", true)), "%s grows with the giant" % id)
		var up: Dictionary = rec.get("upgrade", {})
		var to := GameData.get_record(str(up.get("to", "")))
		assert_eq(int(to.get("fit_max_stage", 10)), 3, "%s reforges into %s, which fits stage 3" % [id, up.get("to")])
		assert_true(float(to.damage_multiplier) > float(rec.damage_multiplier), "and hits harder")
		var cost: Array = up.get("cost", [])
		assert_true(cost.size() == 1 and str(cost[0].item) == "item.iron_ingot" and int(cost[0].count) == 2,
			"for 2 iron ingots (%s)" % [cost])
		assert_eq(str(to.get("light_chain", "")), str(rec.get("light_chain", "")), "the same moveset")
	assert_eq(PlayerEquipment.upgrade_problems(GameData.records), PackedStringArray(),
		"every upgrade fits at least as high as its source")
	var bad := {"weapon.a": {"type": "weapon", "fit_max_stage": 3, "upgrade": {"to": "weapon.b"}},
		"weapon.b": {"type": "weapon", "fit_max_stage": 2}}
	assert_eq(PlayerEquipment.upgrade_problems(bad).size(), 1, "an upgrade that fits lower is reported")
	var tree := GameData.get_record("weapon.tree_oak")
	assert_false(bool(tree.scales_with_growth), "the tree has a fixed real size")
	assert_eq(int(tree.required_stage), 3, "stage 3 only")
	assert_eq(str(tree.required_permission), "tree_weapon", "with the tree_weapon permission")
	assert_true((tree.tags as Array).has("TreeWeapon"), "its blows carry TreeWeapon")
	for wid: String in WEAPONS + ["weapon.tree_oak"]:
		var w := GameData.get_record(wid)
		for key: String in ["light_chain", "heavy"]:
			var id := str(w[key])
			var guard := 0
			while id != "" and guard < 8:
				var a := GameData.get_action(id)
				assert_true(a != null and a.tags.has("BasicAttack"), "%s (%s) builds fury (BasicAttack)" % [id, wid])
				if wid == "weapon.tree_oak":
					assert_true(a.tags.has("TreeWeapon"), "%s carries TreeWeapon" % id)
				id = a.chain_next if a != null else ""
				guard += 1
	assert_eq(GameData.get_action("ability.hammer_light_1").chain_next, "ability.hammer_light_2", "the maul's 2-blow chain")
	assert_eq(GameData.get_action("ability.hammer_light_2").chain_next, "", "ends after two")
	assert_true(GameData.get_action("ability.sword_light_1").windup_ticks < GameData.get_action("ability.light_1").windup_ticks,
		"the sword's chain is faster than the club's")
	assert_true(GameData.get_action("ability.hammer_heavy").poise_damage > GameData.get_action("ability.heavy_1").poise_damage,
		"the maul's slam breaks more poise")


func test_weapon_schema_fields_and_checks() -> void:
	var good := {"schema_version": 1, "id": "weapon.test_good", "type": "weapon", "family": "sword",
		"damage_multiplier": 1.0, "length_m": 1.0, "hit_radius_m": 0.2, "scales_with_growth": true,
		"fit_max_stage": 2, "visual_shape": "sword", "light_chain": "ability.sword_light_1", "heavy": "ability.sword_heavy",
		"required_stage": 1, "required_permission": "tree_weapon", "tags": ["TreeWeapon"],
		"upgrade": {"to": "weapon.sword_reinforced", "cost": [{"item": "item.iron_ingot", "count": 2}]}}
	assert_eq(DataValidator.validate_record(good, "good.json").errors, PackedStringArray(), "every P08 weapon field validates")
	var cases := [
		[{"visual_shape": "axe"}, "visual_shape"],
		[{"fit_max_stage": 11}, "fit_max_stage"],
		[{"upgrade": {"to": "weapon.test_good", "cost": []}}, "cannot upgrade into itself"],
		[{"required_stage": 3, "fit_max_stage": 2}, "would never fit"],
		[{"upgrade": {"to": "weapon.sword_reinforced", "cost": [{"item": "item.iron_ingot", "count": 0}]}}, "count"],
		[{"required_permission": "fly"}, "required_permission"],
	]
	for c: Array in cases:
		var rec := good.duplicate(true)
		rec.merge(c[0], true)
		var errors: PackedStringArray = DataValidator.validate_record(rec, "bad.json").errors
		assert_true(not errors.is_empty() and str(errors).contains(c[1]), "%s is refused (%s)" % [c[0], errors])


# --------------------------------------------------------------------------- equipping

func test_equipping_is_refused_mid_swing_and_the_tree_below_stage_3() -> void:
	var p := await _grounded_player()
	assert_eq(p.equipment.weapon_id(), "weapon.club", "the giant starts with the club")
	assert_eq(p.equipment.owned(), PackedStringArray(["weapon.club"]), "and owns only it")
	assert_eq(p.equipment.equip_weapon("weapon.sword").reason, "not_owned", "a weapon it does not own")
	assert_eq(p.equipment.equip_weapon("weapon.nope").reason, "unknown", "an unknown id")
	assert_true(p.equipment.grant_weapon("weapon.sword").ok, "granted without equipping")
	assert_eq(p.equipment.weapon_id(), "weapon.club", "still holding the club")
	p.router.inject_light_attack()
	await step_ticks(3)
	assert_eq(p.controller.state, CombatController.State.ATTACKING, "mid-swing")
	var refused: Dictionary = p.equipment.equip_weapon("weapon.sword")
	assert_eq(refused.reason, "busy", "equipping is refused mid-swing")
	assert_eq(p.equipment.weapon_id(), "weapon.club", "the club stays")
	assert_near(p.weapon_length, 1.85, 1e-6, "and the sweep keeps its length")
	assert_true(equipped.is_empty(), "no weapon_equipped")
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	var ok: Dictionary = p.equipment.equip_weapon("weapon.sword")
	assert_true(ok.ok, "back in LOCOMOTION the sword is equipped (%s)" % ok.reason)
	assert_eq(p.weapon.get("id"), "weapon.sword", "player.weapon is the sword")
	assert_eq(p.controller.loadout.light, "ability.sword_light_1", "its light chain")
	assert_eq(p.controller.loadout.heavy, "ability.sword_heavy", "its heavy")
	assert_true(p.controller.library.has("ability.sword_light_3"), "the whole chain is in the library")
	assert_near(p.weapon_length, 1.6, 1e-6, "the sweep follows the sword's length")
	assert_near(p.weapon_radius, 0.3, 1e-6, "and its radius")
	assert_eq(equipped, ["weapon.sword"] as Array[String], "weapon_equipped once")
	assert_eq(loadout_events, 1, "loadout_changed once")
	p.router.inject_light_attack()
	await step_ticks(2)
	assert_eq(p.controller.action_id(), "ability.sword_light_1", "the next light is the sword's")
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	var tree: Dictionary = p.equipment.grant_weapon("weapon.tree_oak", true)
	assert_eq(tree.reason, "stage", "the tree is refused at stage 1 (%s)" % tree.message)
	assert_true(p.equipment.owns("weapon.tree_oak"), "but it is owned")
	await _grow(p, 2)
	assert_eq(p.equipment.equip_weapon("weapon.tree_oak").reason, "stage", "and at stage 2")
	await _grow(p, 3)
	var lifted: Dictionary = p.equipment.equip_weapon("weapon.tree_oak")
	assert_true(lifted.ok, "a stage-3 giant wields it (%s)" % lifted.reason)
	assert_eq(p.controller.loadout.light, "ability.tree_light_1", "the tree's sweeps")
	assert_near(p.weapon_length, 7.5, 1e-6, "the tree keeps its real length")
	assert_near(p.equipment.effective_weapon_scale(), 1.0, 1e-9, "a fixed-size weapon is never scaled")
	TestFixtures.record_override("growth.03", {"interaction_permissions": ["grab_small", "throw_boulder"]})
	assert_true(p.equipment.equip_weapon("weapon.club").ok, "back to the club")
	p.set_profile(GameData.get_record("growth.03"))
	assert_eq(p.equipment.equip_weapon("weapon.tree_oak").reason, "permission",
		"without the tree_weapon permission the tree is refused")


## The weapon mesh replaces the generated club: under Visual/Body/ShoulderR as "Weapon", the
## generated Club hidden, the tree's canopy on render layer 2 (first person hides it).
func test_the_weapon_mesh_replaces_the_generated_club() -> void:
	var p := await _grounded_player()
	var arm := p.get_node("Visual/Body/ShoulderR")
	var club := arm.get_node("Club") as Node3D
	assert_false(club.visible, "the generated Club is hidden")
	assert_true(arm.get_node_or_null("Weapon") == p.equipment.visual, "the equipment's mesh is the Weapon node")
	_equip(p, "weapon.hammer")
	await step_ticks(1)
	assert_eq(arm.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Weapon")).size(), 1,
		"one weapon mesh at a time")
	assert_true(p.equipment.visual.has_node("Head"), "the maul's head")
	await _grow(p, 3)
	_equip(p, "weapon.tree_oak")
	await step_ticks(1)
	var canopy := p.equipment.visual.get_node("Canopy") as MeshInstance3D
	assert_eq(canopy.layers, CameraRig.FP_HIDDEN_LAYER, "the canopy is on the first-person-hidden layer")
	assert_eq(p.rig.idle_arm_pose, WeaponVisuals.TREE_IDLE_POSE, "the tree is carried raised to the right")
	var k := PlayerGrowth.body_scale_for(p.profile)
	assert_near(p.equipment.visual.scale.x, 1.0 / k, 1e-4, "the tree's node undoes k (real size)")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(2)
	assert_true(p.camera_rig.is_first_person(), "first person")
	assert_eq(p.camera_rig.camera.cull_mask & canopy.layers, 0, "the camera does not draw the canopy")
	_equip(p, "weapon.club")
	assert_true(p.rig.idle_arm_pose != WeaponVisuals.TREE_IDLE_POSE, "the club gets the rig's own rest pose back")


## The mesh is as long as the sweep (within 2 %) for the club, sword and maul at stages 1-3, and
## the sweep's length is the weapon's length x the weapon scale of min(stage, fit stage).
func test_visual_length_matches_the_sweep_at_every_stage() -> void:
	var p := await _grounded_player()
	for id: String in WEAPONS + ["weapon.sword_reinforced"]:
		_equip(p, id)
	for stage in [1, 2, 3]:
		await _grow(p, stage)
		for id: String in WEAPONS + ["weapon.sword_reinforced"]:
			assert_true(p.equipment.equip_weapon(id).ok, "%s equipped at stage %d" % [id, stage])
			await step_ticks(1)
			var rec := GameData.get_record(id)
			var fit := mini(stage, int(rec.get("fit_max_stage", 10)))
			var scale := float(PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), fit).weapon_scale)
			assert_near(p.weapon_length, float(rec.length_m) * scale, 1e-4,
				"stage %d %s: the sweep is %.2f x the stage-%d scale" % [stage, id, rec.length_m, fit])
			var visual: float = p.equipment.visual_length()
			assert_true(absf(visual - p.weapon_length) <= 0.02 * p.weapon_length,
				"stage %d %s: the mesh (%.3f m) matches the sweep (%.3f m) within 2%%" % [stage, id, visual, p.weapon_length])
	_equip(p, "weapon.tree_oak")
	await step_ticks(1)
	assert_true(absf(p.equipment.visual_length() - 7.5) <= 0.15, "the tree's mesh is 7.5 m long (%.2f)" % p.equipment.visual_length())


## The swing reaches as far as it should: the tip at arm + weapon length from the shoulder (the
## §4.8 reach table), and a light of each weapon lands on a soldier 0.6 x melee reach in front at
## the stages it fits (stage 3: the reforged blade).
func test_the_swing_reaches_the_expected_distance_per_stage() -> void:
	var reach := {}
	var p := await _grounded_player()
	p.entity.combatant.unkillable = true
	for id: String in WEAPONS + ["weapon.sword_reinforced", "weapon.hammer_reinforced", "weapon.club_reinforced", "weapon.tree_oak"]:
		p.equipment.grant_weapon(id)
	var n := 0
	for stage in [1, 2, 3]:
		await _grow(p, stage)
		var ids: Array = ["weapon.club", "weapon.sword", "weapon.hammer"] if stage < 3 \
			else ["weapon.club_reinforced", "weapon.sword_reinforced", "weapon.hammer_reinforced", "weapon.club", "weapon.tree_oak"]
		for id: String in ids:
			assert_true(p.equipment.equip_weapon(id).ok, "%s at stage %d" % [id, stage])
			var light := str(p.controller.loadout.light)
			var seg := p.weapon_segment_global(GameData.get_action(light), 0.5)
			var tip_from_pivot := seg[1].distance_to(p.to_global(p.weapon_pivot))
			assert_near(tip_from_pivot, p.arm_length + p.weapon_length, 1e-3, "stage %d %s: the tip is arm + weapon from the shoulder" % [stage, id])
			reach["%d:%s" % [stage, id]] = p.arm_length + p.weapon_length
			if id == "weapon.tree_oak" or (stage == 3 and id == "weapon.club"):
				continue
			n += 1
			var d := 0.6 * float(p.profile.melee_reach_m)
			var sid := "test.reach_%d" % n
			var s := spawn_soldier(Vector3(0, 0.05, -d), 0.0, sid)
			s.entity.combatant.unkillable = true
			p.camera_rig.yaw = 0.0
			await step_ticks(2)
			assert_eq(await _swing(p, light, sid), 1, "stage %d %s: its first light lands on a soldier %.2f m in front" % [stage, id, d])
			s.queue_free()
			await step_ticks(1)
	assert_near(float(reach["1:weapon.club"]), 3.35, 0.05, "stage 1 club reach about 3.5 m (§4.8)")
	assert_true(float(reach["2:weapon.club"]) >= 4.8 and float(reach["2:weapon.club"]) <= 5.1, "stage 2 about 4.8-5.0 m")
	assert_true(float(reach["3:weapon.club_reinforced"]) >= 6.5 and float(reach["3:weapon.club_reinforced"]) <= 7.3,
		"stage 3 reforged 6.5-7.3 m (%.2f)" % reach["3:weapon.club_reinforced"])
	assert_true(float(reach["3:weapon.club"]) >= 5.5 and float(reach["3:weapon.club"]) <= 6.1,
		"stage 3 unreforged about 5.5-6 m (%.2f)" % reach["3:weapon.club"])
	assert_true(float(reach["3:weapon.tree_oak"]) > float(reach["3:weapon.club_reinforced"]) + 3.0,
		"the tree reaches much farther (%.2f m)" % reach["3:weapon.tree_oak"])


## An unreforged sword (fits stage 2) at stage 3 keeps its stage-2 length, the HUD warns once, the
## inventory marks it, and its heavy still lands on a soldier at the giant's feet; the reforged
## Kingsguard Blade scales to stage 3.
func test_an_unreforged_sword_at_stage_3_keeps_its_stage_2_length() -> void:
	var p := await _grounded_player()
	p.entity.combatant.unkillable = true
	_equip(p, "weapon.sword")
	await _grow(p, 2)
	var stage2_length := p.weapon_length
	assert_near(stage2_length, 1.6 * 1.5, 1e-4, "stage 2: the sword fits (x1.5)")
	assert_false(p.equipment.is_too_small(), "not too small at stage 2")
	messages.clear()
	await _grow(p, 3)
	assert_true(p.equipment.is_too_small(), "too small at stage 3")
	assert_near(p.weapon_length, stage2_length, 1e-4, "it keeps its stage-2 length (%.3f m)" % p.weapon_length)
	assert_near(p.weapon_radius, 0.3 * 1.5, 1e-4, "and radius")
	assert_eq(p.equipment.fit_stage(), 2, "the stage it fits")
	var warning := PlayerEquipment.FIT_WARNING % "Kingsguard Sword"
	assert_eq(messages.count(warning), 1, "the HUD warns once (%s)" % [messages])
	assert_true(absf(p.equipment.visual_length() - stage2_length) <= 0.02 * stage2_length, "the mesh is as small as the sweep")
	assert_eq(p.equipment.weapon_label("weapon.sword"), "Kingsguard Sword (too small)", "the inventory marks it")
	assert_eq(p.equipment.weapon_label("weapon.sword_reinforced"), "Kingsguard Blade", "but not the blade")
	var feet := float(p.profile.capsule_radius_m) + 0.35 + 0.1
	var s := spawn_soldier(Vector3(0, 0.05, -feet), 0.0, "test.feet_soldier")
	s.entity.combatant.unkillable = true
	p.camera_rig.yaw = 0.0
	await step_ticks(2)
	assert_eq(await _swing(p, "ability.sword_heavy", "test.feet_soldier"), 1,
		"its heavy still lands on a soldier at the giant's feet (%.2f m)" % feet)
	messages.clear()
	_equip(p, "weapon.sword_reinforced")
	assert_near(p.weapon_length, 1.6 * 2.1667, 1e-3, "the reforged blade scales to stage 3")
	assert_false(p.equipment.is_too_small(), "and fits")
	assert_false(messages.has(PlayerEquipment.FIT_WARNING % "Kingsguard Blade"), "no warning for it")
	_equip(p, "weapon.sword")
	assert_true(messages.has(warning), "equipping the outgrown sword warns again")
	await _grow(p, 2)
	assert_false(p.equipment.is_too_small(), "shrinking back to stage 2: it fits again")
	assert_near(p.weapon_length, stage2_length, 1e-4, "at its stage-2 length")


func test_the_swords_first_light_grants_4_fury() -> void:
	var p := await _grounded_player()
	_equip(p, "weapon.sword")
	var s := spawn_soldier(Vector3(0, 0.05, -2.1), 0.0, "test.fury_soldier")
	s.entity.combatant.unkillable = true
	await step_ticks(2)
	var before := p.entity.combatant.pools.fury
	p.router.inject_light_attack()
	var hit: bool = await TestWait.until(self, func() -> bool: return not hits_on("test.fury_soldier").is_empty(), 40)
	assert_true(hit, "the sword's first light lands")
	if hit:
		var r: HitResult = hits_on("test.fury_soldier")[0]
		assert_eq(r.event.action_id, "ability.sword_light_1", "with the sword's first light")
		assert_eq(r.outcome, HitResult.Outcome.HIT, "a clean hit")
		assert_near(r.event.weapon_multiplier, 0.95, 1e-6, "with the sword's multiplier")
	assert_near(p.entity.combatant.pools.fury - before, 4.0, 1e-6, "and grants 4 fury (BasicAttack)")


## Save keys: weapon and weapons_owned. A restore equips silently (no events, no warning), with
## the weapon's moveset and the stage-capped length.
func test_equipment_state_round_trips_silently() -> void:
	var p := await _grounded_player()
	_equip(p, "weapon.hammer")
	p.equipment.grant_weapon("weapon.sword")
	await _grow(p, 3)
	var state := p.capture_character_state()
	assert_eq(state.weapon, "weapon.hammer", "the weapon key")
	assert_eq(state.weapons_owned, ["weapon.club", "weapon.hammer", "weapon.sword"], "the owned weapons, in order")
	var normalized := CharacterState.normalize(state)
	assert_eq(normalized.weapons_owned, ["weapon.club", "weapon.hammer", "weapon.sword"], "CharacterState keeps them")
	p.queue_free()
	await step_ticks(2)
	equipped.clear()
	messages.clear()
	loadout_events = 0
	var q := await _grounded_player(Vector3(0, 0.05, 10))
	q.apply_character_state(normalized)
	await step_ticks(2)
	assert_eq(q.growth_stage, 3, "the stage comes back first")
	assert_eq(q.equipment.weapon_id(), "weapon.hammer", "then the maul")
	assert_eq(q.equipment.owned(), PackedStringArray(["weapon.club", "weapon.hammer", "weapon.sword"]), "and what it owns")
	assert_eq(q.controller.loadout.light, "ability.hammer_light_1", "with its moveset")
	assert_near(q.weapon_length, 1.5 * 1.5, 1e-4, "capped at its fit stage")
	assert_true(equipped.is_empty() and loadout_events == 0, "a restore emits nothing")
	assert_false(messages.has(PlayerEquipment.FIT_WARNING % "Raider's Maul"), "and shows no warning")
	var dropped := CharacterState.sanitize({"definition_id": "player.giant", "level": 1, "weapon": "weapon.gone",
		"weapons_owned": ["weapon.sword", "weapon.gone"]})
	assert_eq(dropped.data.weapon, "weapon.club", "an unknown saved weapon falls back to the record's")
	assert_eq(dropped.data.weapons_owned, ["weapon.sword"], "and is dropped from the owned list")


# --------------------------------------------------------------------------- first person

## First person at stage 3 with the sword, the hammer and the tree in turn, through a light chain
## entered with the router: the crosshair probe never reports more than 30 consecutive ticks in
## which the giant's own meshes (its weapon included) are the first thing the centre ray meets.
func test_first_person_light_chains_keep_the_crosshair_clear_at_stage_3() -> void:
	var p := await _grounded_player()
	p.entity.combatant.unkillable = true
	await _grow(p, 3)
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(2)
	assert_true(p.camera_rig.is_first_person(), "first person")
	for id: String in ["weapon.sword", "weapon.hammer", "weapon.tree_oak"]:
		assert_true(_equip(p, id).ok, "%s equipped" % id)
		await step_ticks(2)
		var probe := CrosshairProbe.new(p.camera_rig.camera, [p])
		var chain := 3 if id == "weapon.sword" else 2
		for pitch_deg: float in [0.0, -25.0]:
			p.camera_rig.pitch = deg_to_rad(pitch_deg)
			for i in chain:
				p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
				p.router.inject_light_attack()
				for t in 30:
					await step_ticks(1)
					probe.sample()
			await TestWait.until(self, func() -> bool:
				probe.sample()
				return p.controller.state == CombatController.State.LOCOMOTION, 120)
		assert_true(probe.samples > 100, "%s: sampled the chains (%d ticks)" % [id, probe.samples])
		assert_true(probe.max_consecutive <= MAX_OBSCURED_TICKS,
			"%s: never more than %d obscured ticks in a row (worst %d by %s; %d of %d obscured)" % [id,
			MAX_OBSCURED_TICKS, probe.max_consecutive, probe.worst_blocker, probe.obscured_ticks, probe.samples])
