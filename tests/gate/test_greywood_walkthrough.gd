extends IntegrationSuite
## The Greywood walkthrough (P35; plan M6-M9 §3.19, §5.4, §5.5, §5.7, §5.13), teleport-assisted: the
## campaign started from world_start in level.world with Quests over every shipped quest, the giant
## grown to its stage, and the shipped chunks' props parts (the troll den's, the woodcutters' camp's
## with the Needle, the great pines') struck, heaved and burned by the giant; the Matriarch is the
## shipped enemy scene. The woodfolk's oath is won as the first oath:
##   * by slaying the Matriarch at stage 4 (Sedge's report: 750 XP, the feast's 2 attribute points);
##   * by driving her out at stage 4: the three den braziers smashed burn the three brood nests (50 XP
##     each), the woodfolk pull the back wall down 20 s later, and below 60 % she flees through it
##     (600 XP at Sedge's);
##   * by driving her out at stage 5 with the heave shortcut: the giant heaves the wall aside at once;
## and after each: the oath done with its outcome, the oath's reward, the XP floored at level 9, the
## woodfolk allied. Besides: the woodcutters' bonfire sets a troll beside it burning, the great pine
## is uprooted at stage 4 (not 3), and the Needle's slot fits stages 3-4 and refuses 5.

const START_CP := "world.cp.hollowmere"
## The den spans two chunks: the wall, the first nest and brazier; the other two and the pines.
const DEN_PARTS := ["res://scenes/world/chunks/c0_2_0.tscn", "res://scenes/world/chunks/c1_2_0.tscn"]
const CAMP_PART := "res://scenes/world/chunks/c2_4_0.tscn"
const WOOD := "quest.oath_wood"
const MATRIARCH := "world.greywood.troll_matriarch"
const BRAZIERS := ["world.greywood.den_brazier_1", "world.greywood.den_brazier_2", "world.greywood.den_brazier_3"]
const NESTS := ["world.greywood.den_nest_1", "world.greywood.den_nest_2", "world.greywood.den_nest_3"]
const WALL := "world.greywood.troll_den_wall"


func before_each() -> void:
	await super()
	WorldState.clear()


## The campaign from world_start in level.world, the giant on the suite's floor at `stage`.
func _start(stage: int) -> GiantPlayer:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	await _settle()
	var grown := int(p.get("growth_stage")) == stage
	for i in 240:
		if grown or bool(p.growth.debug_set_stage(stage).get("ok", false)):
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage %d" % stage)
	await _settle()
	return p


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


func _part(path: String) -> Node3D:
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	return part


## The troll den's props parts (both chunks); the suite's world holds them.
func _den() -> Node3D:
	for path: String in DEN_PARTS:
		_part(path)
	return world


func _find(root: Node, world_id: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


## Strikes a prop as the giant until it is destroyed (at most 40 blows).
func _strike(p: GiantPlayer, world_id: String) -> bool:
	for i in 40:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			break
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = world_id
		h.power = 600.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = int(p.get("growth_stage"))
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	await step_ticks(2)
	return WorldState.is_destroyed(world_id)


func _talk(outcome: String, expect_node: String) -> void:
	var s := Quests.start_dialogue("dialogue.sedge", "world.greywood.sedge")
	assert_true(s != null, "Sedge talks")
	if s == null:
		return
	assert_eq(str(s.node().get("id", "")), expect_node, "Sedge opens with %s" % expect_node)
	assert_true(s.find_choice(outcome) >= 0, "the %s choice is offered" % outcome)
	s.choose_outcome(outcome)
	Quests.end_dialogue()
	await _settle()


## The Matriarch, spawned on the suite's floor (her outcome is hers wherever she stands).
func _matriarch() -> TrollEnemy:
	var rec := GameData.get_record("enemy.troll_matriarch")
	var m := (load(str(rec.scene)) as PackedScene).instantiate() as TrollEnemy
	m.set("entity_id", MATRIARCH)
	m.position = Vector3(0, 0.05, 40)
	world.add_child(m)
	await step_ticks(2)
	return m


## The drive-out: below 60 % she runs for her exit; there she is gone.
func _drive_her_out(m: TrollEnemy) -> void:
	var pools := m.entity.combatant.pools
	pools.health = pools.health_max * 0.55
	await step_ticks(2)
	assert_true(m.is_fleeing(), "below 60 % with the nests burned and the wall open she runs")
	m.global_position = m.exit_point() + Vector3(0, 0.05, 1.0)
	await step_ticks(3)
	assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "fled", "her outcome: fled")


func _sworn(p: GiantPlayer, outcome: String) -> void:
	assert_eq(Quests.quest_state(WOOD), Quests.COMPLETED, "the woodfolk's oath is won by %s" % outcome)
	assert_eq(str(WorldState.get_flag("oath.wood.outcome")), outcome, "its outcome")
	assert_true(QuestConditions.truthy(WorldState.get_flag("oath.wood.done")), "oath.wood.done")
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.woodfolk.allied")), "the woodfolk are allies")
	assert_true(p.progression.level >= 9, "the XP is floored at level 9 (%d)" % p.progression.level)
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON), 1, "the oath's titan iron")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON), 3, "world_start's iron and the oath's 2")
	var c := QuestConditions.empty_context()
	c.flags = WorldState.flags
	assert_true(QuestConditions.all_hold(GameData.get_record("shrine.world_greywood").growth_requires_conditions, c),
		"the stage-5 shrines open after the first oath")


func _met(p: GiantPlayer) -> void:
	assert_eq(Quests.quest_state(WOOD), Quests.ACTIVE, "the woodfolk's oath starts at stage %d" % int(p.get("growth_stage")))
	await _talk("accept", "greet")
	assert_eq(Quests.stage_of(WOOD), "den", "met: the oath waits for the den")


## Smashes the den's three braziers: each sets the brood nest beside it burning.
func _burn_the_nests(p: GiantPlayer, den: Node3D) -> void:
	var xp: int = p.progression.xp
	for i in BRAZIERS.size():
		assert_true(await _strike(p, BRAZIERS[i]), "%s is smashed" % BRAZIERS[i])
		await step_ticks(3)
		assert_true(WorldState.is_destroyed(NESTS[i]), "the fire takes %s" % NESTS[i])
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.nests_burned")), "the den's nests are burned")
	assert_eq(p.progression.xp - xp, 150, "three nests burn for 50 XP each")
	assert_true(_find(den, NESTS[0]) != null, "the nests stood in the den's part")


func test_the_wood_by_slaying_the_matriarch_at_stage_4() -> void:
	var p := await _start(4)
	await _met(p)
	var points: int = p.progression.unspent_attribute_points
	var level: int = p.progression.level
	var m := await _matriarch()
	var pools := m.entity.combatant.pools
	pools.health = 1.0
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = p.entity.entity_id
	h.target_id = MATRIARCH
	h.power = 5000.0
	h.attacker_stat = 40.0
	h.attacker_height_m = 11.0
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.category = "melee"
	h.attacker_growth_stage = 4
	h.attacker_position = m.global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)
	await step_ticks(3)
	assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "slain", "her outcome: slain")
	await _settle()
	assert_eq(Quests.stage_of(WOOD), "swear", "the den is empty: back to Sedge")
	await _talk("slay", "report_slain")
	await _sworn(p, "slay")
	var from_levels: int = (p.progression.level - level) * Progression.attribute_points_per_level()
	assert_eq(p.progression.unspent_attribute_points - points - from_levels, 2, "the woodfolk's feast: 2 attribute points")


func test_the_wood_by_driving_her_out_at_stage_4() -> void:
	var p := await _start(4)
	await _met(p)
	var den := _den()
	var wall := _find(den, WALL) as DenWall
	assert_true(wall != null and not wall.is_open(), "the den's back wall stands")
	await _burn_the_nests(p, den)
	await step_ticks(ActionDef.seconds_to_ticks(19.0))
	assert_false(wall.is_open(), "the woodfolk need their 20 s")
	await step_ticks(ActionDef.seconds_to_ticks(1.5))
	assert_true(wall.is_open(), "then they pull the wall down")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.wall_open")), "the way out is open")
	var m := await _matriarch()
	await _drive_her_out(m)
	await _settle()
	await _talk("drive", "report_fled")
	await _sworn(p, "drive")


func test_the_wood_by_driving_her_out_with_the_stage_5_heave() -> void:
	var p := await _start(5)
	await _met(p)
	var den := _den()
	var wall := _find(den, WALL) as DenWall
	var heave := wall.get_node_or_null("HeavePoint") as HeavePoint
	assert_true(heave != null, "the wall has its heave point")
	heave.interact(p)
	await step_ticks(3)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.wall_open")), "a stage-5 giant heaves the wall aside at once")
	await _burn_the_nests(p, den)
	var m := await _matriarch()
	await _drive_her_out(m)
	await _settle()
	await _talk("drive", "report_fled")
	await _sworn(p, "drive")


func test_the_camp_s_fire_the_great_pine_and_the_needle() -> void:
	var p := await _start(3)
	# The woodcutters' bonfire: smashed beside a troll, it sets the troll burning (the fire lesson).
	var camp := _part(CAMP_PART)
	var fire := _find(camp, "world.greywood.woodcutters_bonfire") as Node3D
	assert_true(fire != null, "the camp's bonfire")
	var rec := GameData.get_record("enemy.troll")
	var troll := (load(str(rec.scene)) as PackedScene).instantiate() as TrollEnemy
	troll.set("entity_id", "world.test.camp_troll")
	troll.position = fire.global_position + Vector3(3, 0.5, 0)
	troll.set("ai_enabled", false)
	world.add_child(troll)
	await step_ticks(2)
	assert_false(troll.p34_has_status_tag("Burning"), "the troll does not burn yet")
	assert_true(await _strike(p, "world.greywood.woodcutters_bonfire"), "the bonfire is scattered")
	await step_ticks(2)
	assert_true(troll.p34_has_status_tag("Burning"), "the troll beside it burns")
	assert_true(GameData.has_record("tutorial.troll_fire"), "and the camp teaches it")
	# The Needle: its sign answers a giant too big for the slot, and the slot's width decides.
	var pass_ := _find_class(camp, "NarrowPass") as NarrowPass
	assert_true(pass_ != null, "the Needle's sign")
	assert_false(pass_.refuse(p), "a stage-3 giant fits")
	var gap := _needle_gap()
	for s: int in [3, 4, 5]:
		var r := float(GameData.get_record("growth.%02d" % s).capsule_radius_m)
		assert_eq(2.0 * r < gap, s <= 4, "stage %d: %.1f m across in a %.2f m slot" % [s, 2.0 * r, gap])
	# The great pine: rooted too deep at stage 3, torn out at stage 4.
	_part(DEN_PARTS[1])
	var pine := _find(world, "world.greywood.great_pine_1") as GreatPineTree
	assert_true(pine != null, "the great pine")
	assert_false(pine.can_interact(p), "a stage-3 giant cannot uproot it")
	var grown := false
	for i in 240:
		if bool(p.growth.debug_set_stage(5 if i > 200 else 4).get("ok", false)) and int(p.get("growth_stage")) == 4:
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage 4")
	assert_true(pine.can_interact(p), "a stage-4 giant can")
	pine.interact(p)
	await step_ticks(2)
	assert_eq(p.equipment.weapon_id(), "weapon.tree_pine", "and wields the pine")
	assert_true(WorldState.is_destroyed("world.greywood.great_pine_1"), "the pine is gone from the earth")
	var signals: Array = []
	var on_blocked := func(_t: int, gate: String, _s: int, _m: String) -> void: signals.append(gate)
	Events.size_gate_blocked.connect(on_blocked)
	for i in 240:
		if bool(p.growth.debug_set_stage(5).get("ok", false)):
			break
		await step_ticks(1)
	assert_true(pass_.refuse(p, Sim.tick + 1000), "a stage-5 giant has outgrown the Needle")
	Events.size_gate_blocked.disconnect(on_blocked)
	assert_eq(signals, ["world.gate.needle"], "the sign says so")


func _find_class(root: Node, cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() != null and (n.get_script() as Script).get_global_name() == cls:
			return n
	return null


## The Needle's slot: the distance between its two walls' centre lines less their thickness.
func _needle_gap() -> float:
	var walls: Array = WorldContent.elements().filter(func(el: Dictionary) -> bool:
		return str(el.get("id", "")) in ["world.greywood.needle_wall_west", "world.greywood.needle_wall_east"])
	var a := Vector2(float(walls[0].pos[0]), float(walls[0].pos[1]))
	var b := Vector2(float(walls[1].pos[0]), float(walls[1].pos[1]))
	return a.distance_to(b) - float(walls[0].size[2])
