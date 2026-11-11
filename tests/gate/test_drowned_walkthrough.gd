extends IntegrationSuite
## The Drowned Steps walkthrough (P35; plan M6-M9 §3.19, §5.4, §5.5, §5.7, §5.8), teleport-assisted:
## the campaign started from world_start in level.world with Quests over every shipped quest, the giant
## grown to its stage, and the shipped chunks' props parts (the Mere's bells, the Titan's Bones, the
## causeway, the ferrywoman's landing) struck, lit and heaved by the giant:
##   * the bells: Wenna's dialogue starts the quest; the fourth bell hangs in the Wend's deep reach
##     (a stage-4 gate) and the island's past the deep channel (stage 5); the five rung pay 200 XP and
##     open the Stoneknuckles' rack, whose gauntlets end the quest;
##   * the Titan's Bones: the forge's fire waits for the scavengers, then lights (2 titan iron, the
##     quest's 150 XP) and the Titan Forge, cold before, titanforges a reinforced weapon;
##   * the sunken vault: the causeway's rockfall will not move at stage 4 and is heaved at stage 5;
##     walking the vault completes the quest (100 XP).

const START_CP := "world.cp.mere_south"
const BELLS := ["world.drowned.bell_1", "world.drowned.bell_2", "world.drowned.bell_3", "world.drowned.bell_4",
	"world.drowned.bell_5"]
const BELL_PARTS := ["res://scenes/world/chunks/c3_3_0.tscn", "res://scenes/world/chunks/c4_4_0.tscn",
	"res://scenes/world/chunks/c4_3_0.tscn"]
const LANDING_PART := "res://scenes/world/chunks/c3_4_0.tscn"
const BONES_PART := "res://scenes/world/chunks/c4_2_0.tscn"
const VAULT_PART := "res://scenes/world/chunks/c4_4_0.tscn"


func before_each() -> void:
	await super()
	WorldState.clear()


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
	await _grow(p, stage)
	return p


func _grow(p: GiantPlayer, stage: int) -> void:
	var grown := int(p.get("growth_stage")) == stage
	for i in 240:
		if grown or bool(p.growth.debug_set_stage(stage).get("ok", false)):
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage %d" % stage)
	await _settle()


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


func _part(path: String) -> Node3D:
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	return part


func _find(world_id: String) -> Node:
	for n in world.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


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


func test_the_five_bells_and_the_stoneknuckles() -> void:
	var p := await _start(4)
	# Where they hang: the fourth in the Wend's stage-4 deep reach, the fifth past the stage-5 channel.
	var feats := WorldFeatures.new(WorldLayout.load_all().world)
	feats.make_field()   # the gate regions are laid out with the height field
	var b4 := WorldXp.position_of(BELLS[3])
	assert_eq(int(feats.gate_at(b4.x, b4.z)), 32, "the fourth bell hangs in the Wend's deep reach (a stage-4 gate)")
	var b5 := WorldXp.position_of(BELLS[4])
	assert_eq(int(feats.gate_at(b5.x, b5.z)), 0, "the fifth stands on the island")
	var circle: Array = GameData.get_record("poi.ancestral_circle").position_m
	for d: Vector2 in [Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60)]:
		assert_eq(int(feats.gate_at(float(circle[0]) + d.x, float(circle[2]) + d.y)), 64,
			"the deep channel round the island is a stage-5 gate (%s)" % d)
	# Wenna asks.
	var s := Quests.start_dialogue("dialogue.ferrywoman", "world.drowned.ferrywoman")
	assert_true(s != null and s.find_choice("bells") >= 0, "Wenna asks the giant to ring her bells")
	if s == null:
		return
	s.choose_outcome("bells")
	Quests.end_dialogue()
	await _settle()
	assert_eq(Quests.quest_state("quest.drowned_bells"), Quests.ACTIVE, "the bells' quest starts")
	for path: String in BELL_PARTS:
		_part(path)
	var xp: int = p.progression.xp
	for b: String in BELLS:
		assert_true(await _strike(p, b), "%s rings" % b)
	await _settle()
	assert_eq(Quests.stage_of("quest.drowned_bells"), "gauntlets", "the five bells rung")
	assert_true(p.progression.xp - xp >= 200, "and paid 200 XP (%d)" % (p.progression.xp - xp))
	_part(LANDING_PART)
	var rack := _find("world.drowned.stoneknuckles_rack") as RewardRack
	assert_true(rack != null and rack.can_interact(p), "the Stoneknuckles are the bell-ringer's")
	rack.interact(p)
	await _settle()
	assert_eq(p.equipment.weapon_id(), "weapon.fists", "the giant wears them")
	assert_eq(Quests.quest_state("quest.drowned_bells"), Quests.COMPLETED, "the bells' quest is done")
	var thanks := Quests.start_dialogue("dialogue.ferrywoman", "world.drowned.ferrywoman")
	assert_eq(str(thanks.node().get("id", "")) if thanks != null else "", "thanks", "Wenna heard every bell")
	Quests.end_dialogue()


func test_the_titan_forge_lit_and_its_titanforging() -> void:
	var p := await _start(4)
	WorldState.set_flag("discovered.titans_bones", true)
	await _settle()
	assert_eq(Quests.quest_state("quest.titan_bones"), Quests.ACTIVE, "the Titan's Bones' quest starts")
	_part(BONES_PART)
	var fire := _find("world.drowned.titan_forge_fire") as ForgeFire
	var forge := _find("world.drowned.titan_forge") as Forge
	assert_true(fire != null and forge != null, "the forge and its fire stand in the ribs")
	assert_false(forge.is_open(), "the Titan Forge is cold")
	assert_false(fire.light(), "not while the scavengers pick at the bones")
	WorldState.set_flag(EncounterDirector.cleared_flag("encounter.drowned_bones_scavengers"), true)
	assert_true(fire.light(), "lit once they are gone")
	await _settle()
	assert_eq(Quests.quest_state("quest.titan_bones"), Quests.COMPLETED, "the Titan's Bones' quest is done")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON), 2, "the ribs' 2 titan iron")
	assert_true(forge.is_open(), "the Titan Forge burns")
	assert_false(fire.enabled, "its fire steps aside for the forge")
	# A reinforced weapon titanforged with the ribs' titan iron and 2 iron.
	p.equipment.grant_weapon("weapon.club_reinforced", true)
	WorldState.add_item(WorldItems.IRON, 2)
	var r := forge.upgrade(p)
	assert_true(bool(r.get("ok", false)), "the Titan Forge titanforges (%s)" % [r])
	assert_eq(p.equipment.weapon_id(), "weapon.club_titan", "the club is titanforged")


func test_the_sunken_vault_behind_the_causeway_s_rockfall() -> void:
	var p := await _start(4)
	WorldState.set_flag("discovered.causeway", true)
	await _settle()
	assert_eq(Quests.quest_state("quest.sunken_vault"), Quests.ACTIVE, "the vault's quest starts")
	_part(VAULT_PART)
	var rockfall := _find("world.drowned.vault_rockfall") as BreakableProp
	var heave := rockfall.get_node_or_null("HeavePoint") as HeavePoint if rockfall != null else null
	assert_true(heave != null, "the causeway's rockfall has its heave point")
	heave.interact(p)
	await step_ticks(3)
	assert_false(WorldState.is_destroyed("world.drowned.vault_rockfall"), "it will not move for a giant of stage 4")
	await _grow(p, 5)
	heave.interact(p)
	await step_ticks(3)
	assert_true(WorldState.is_destroyed("world.drowned.vault_rockfall"), "a stage-5 giant heaves it aside")
	await _settle()
	assert_eq(Quests.stage_of("quest.sunken_vault"), "vault", "the vault lies open")
	var xp: int = p.progression.xp
	Events.area_entered.emit(Sim.tick, "world.area.sunken_vault", p.entity.entity_id)
	await _settle()
	assert_eq(Quests.quest_state("quest.sunken_vault"), Quests.COMPLETED, "walking the vault completes it")
	assert_true(p.progression.xp - xp >= 100, "100 XP (%d)" % (p.progression.xp - xp))
