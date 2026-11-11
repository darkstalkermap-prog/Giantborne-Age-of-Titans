extends IntegrationSuite
## Thornwick's people and the village faction (P11b, plan §3.13 designs 1-3, decision 17) with the
## real giant, real guards (soldiers of faction "village") and real villagers:
##   * hostile-only rules: Tab near neutral guards locks nothing; a Footfall beside a guard and three
##     villagers hits none of them and leaves the faction neutral; one direct light hit on a guard
##     warns (flag, event, HUD line) and does not turn it hostile; a second within 30 s does - the
##     guards become lockable and attack, villagers flee - and neutral guards never defer a checkpoint;
##   * a second offence 40 s after the first only warns again; one blow counts once;
##   * only the smashed barricade sets quest.village.outcome = "force"; hostility by attacking never does;
##   * standing down sends the guards back to their posts (guard down, still neutral) and the
##     villagers to the nearest reachable shelter, where they stop processing (the village test
##     level: a walled yard's shelter no path reaches is skipped);
##   * the elder is protected (IMMUNE, still an offence), never flees and talks (NpcTalker);
##   * a guard or villager spawned after the village turned hostile spawns hostile / sheltered.

const VILLAGE := "res://scenes/test/village_test.tscn"
const VILLAGER := "res://scenes/npcs/villager.tscn"
const ELDER := "res://scenes/npcs/elder.tscn"
const BARRICADE := "res://scenes/world/cart_barricade.tscn"
const HOSTILE := "faction.village.hostile"
const WARNED := "faction.village.warned"
const STOOD_DOWN := "faction.village.stood_down"
const OUTCOME := "quest.village.outcome"

var faction_events: Array = []
var messages: Array = []


func before_each() -> void:
	await super()
	FactionState.reset_for_tests()
	faction_events.clear()
	messages.clear()
	Events.faction_changed.connect(_on_faction_changed)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for pair: Array in [[Events.faction_changed, _on_faction_changed], [Events.hud_message, _on_message]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	await super()


func _on_faction_changed(tick: int, faction: String, state: String) -> void:
	faction_events.append([tick, faction, state])


func _on_message(text: String, kind: String) -> void:
	messages.append([text, kind])


func _states(state: String) -> Array:
	return faction_events.filter(func(e: Array) -> bool: return e[1] == "village" and e[2] == state)


func _guard(pos: Vector3, yaw: float, id: String, ai := true) -> SoldierEnemy:
	var s: SoldierEnemy = (load(SOLDIER) as PackedScene).instantiate()
	s.entity_id = id
	s.ai_enabled = ai
	s.faction = "village"
	s.position = pos
	s.rotation.y = yaw
	world.add_child(s)
	return s


func _person(scene: String, pos: Vector3, id: String, ai := true) -> Civilian:
	var v := (load(scene) as PackedScene).instantiate() as Civilian
	v.entity_id = id
	v.ai_enabled = ai
	v.position = pos
	world.add_child(v)
	return v


## A direct blow of the giant (team PLAYER) on `target_id`, through the real resolution path.
func _blow(target_id: String, from: Vector3, instance := -1) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = instance if instance >= 0 else Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = target_id
	e.action_id = "ability.light_1"
	e.power = 5.0
	e.attacker_stat = 10.0
	e.attacker_height_m = 3.6576
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee", "Light", "BasicAttack"])
	e.attacker_position = from
	Sim.queue_hit(e)


func _village() -> LevelRoot:
	var level := (load(VILLAGE) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	var map := level.nav_map()
	var ok: bool = await TestWait.until(self, func() -> bool:
		return NavigationServer3D.map_get_iteration_id(map) > 0 \
			and NavigationServer3D.map_get_path(map, Vector3(0, 0, 0), Vector3(0, 0, 20), true, 1).size() > 1, 120)
	assert_true(ok, "the village navmesh answers")
	return level


# --------------------------------------------------------------------------- hostile-only rules

func test_neutral_guards_warn_then_turn_hostile() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var guard := _guard(Vector3(0, 0.05, -2.6), PI, "test.guard")
	var folk := [_person(VILLAGER, Vector3(2.2, 0.05, -1.4), "test.villager_1"),
		_person(VILLAGER, Vector3(-2.2, 0.05, -1.4), "test.villager_2"),
		_person(VILLAGER, Vector3(0.4, 0.05, 2.4), "test.villager_3")]
	var far := _person(VILLAGER, Vector3(0, 0.05, 30), "test.villager_far")
	var dummy := spawn_dummy(Vector3(-1.8, 0.05, 1.6), "test.dummy")
	await step_ticks(30)
	assert_eq(guard.entity.team, CombatEntity.Team.NEUTRAL, "a village guard spawns neutral")
	assert_eq(guard.faction_standing, "neutral", "standing neutral")
	assert_eq(guard.brain.state, EnemyBrain.AIState.HOLD, "it holds its post")
	assert_false(guard.brain.aware, "watching the giant without becoming aware")
	assert_true(guard.is_guarding(), "guard up while it watches the giant")
	assert_false(TargetingRules.player_may_target(guard.entity), "the player may not target it")
	for b in GameSession.checkpoint_blockers():
		assert_false(str(b).begins_with("aware:"), "a neutral guard never defers a checkpoint (%s)" % b)
	# Tab near the neutral guard and the villagers: nothing to lock (the dummy is behind the giant).
	p.router.inject_edge(&"lock_press")
	await step_ticks(3)
	assert_true(p.locked_entity() == null, "Tab locks nothing")
	# Heavy Footfall beside the guard and three villagers: only the dummy is struck.
	p.router.inject_edge(&"slot_1")
	await TestWait.until(self, func() -> bool: return started.has("player:ability.heavy_footfall"), 20)
	await step_ticks(50)
	assert_true(started.has("player:ability.heavy_footfall"), "the Footfall went off")
	assert_true(hits_on("test.dummy").size() > 0, "it struck the dummy beside the giant")
	assert_eq(hits_on("test.guard").size(), 0, "not the guard")
	for v: Civilian in folk:
		assert_eq(hits_on(v.entity_id).size(), 0, "not %s" % v.entity_id)
	assert_eq(FactionState.standing("village"), "neutral", "the faction stays neutral")
	assert_true(_states("warned").is_empty(), "no warning")
	# One direct light hit on the guard: a warning, no hostility.
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 60)
	p.router.inject_light_attack()
	var struck: bool = await TestWait.until(self, func() -> bool: return hits_on("test.guard").size() > 0, 60)
	assert_true(struck, "the light connects with the guard")
	await step_ticks(2)
	assert_true(FactionState.is_warned("village") and WorldState.get_flag(WARNED) == true, "faction.village.warned")
	assert_eq(_states("warned").size(), 1, "faction_changed warned")
	assert_true(messages.has([FactionState.text_for("village", "warned"), "warn"]),
		"the HUD warns: %s" % FactionState.text_for("village", "warned"))
	assert_false(FactionState.is_hostile("village"), "one blow does not turn the village hostile")
	assert_eq(guard.entity.team, CombatEntity.Team.NEUTRAL, "the guard stays neutral")
	assert_true(FactionState.text_for("village", "warned").begins_with("Thornwick's people cower. Strike again"),
		"the plan's warning text")
	# A second blow within 30 s: hostile.
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	var before := hits_on("test.guard").size()
	p.router.inject_light_attack()
	await TestWait.until(self, func() -> bool: return hits_on("test.guard").size() > before, 60)
	await step_ticks(2)
	assert_true(FactionState.is_hostile("village"), "a second offence within 30 s: faction.village.hostile")
	assert_eq(_states("hostile").size(), 1, "faction_changed hostile, once")
	assert_eq(guard.faction_standing, "hostile", "the guard turned hostile")
	assert_eq(guard.entity.team, CombatEntity.Team.ENEMY, "team ENEMY")
	assert_true(TargetingRules.player_may_target(guard.entity) and guard.entity.is_lockable(), "now lockable")
	assert_eq(WorldState.get_flag(OUTCOME), null, "attacking the village never sets the outcome")
	p.router.inject_edge(&"lock_press")
	await step_ticks(3)
	assert_true(p.locked_entity() == guard.entity, "Tab locks the hostile guard")
	var attacked: bool = await TestWait.until(self, func() -> bool:
		return started.any(func(s: String) -> bool: return s.begins_with("test.guard:")), 180)
	assert_true(attacked, "the hostile guard attacks")
	assert_true(guard.brain.aware, "and is aware of the giant")
	var fled: bool = await TestWait.until(self, func() -> bool: return far.brain.state != CivilianBrain.State.IDLE, 30)
	assert_true(fled, "a villager 30 m away flees once the village is hostile")
	assert_eq(far.brain.flee_reason, "hostile", "because the village turned hostile")
	for v: Civilian in folk:
		assert_true(v.brain.state != CivilianBrain.State.IDLE, "%s fled the fight beside it" % v.entity_id)
	assert_true(is_instance_valid(dummy), "control: the dummy stood there all along")


func test_an_offence_after_30_s_only_warns_again_and_a_blow_counts_once() -> void:
	assert_eq(FactionState.offence_result(true, 1000, 1000 + 1800, 1800), "hostile", "within 30 s of a warning")
	assert_eq(FactionState.offence_result(true, 1000, 1000 + 1801, 1800), "warned", "after 30 s: warned again")
	assert_eq(FactionState.offence_result(false, 1000, 1001, 1800), "warned", "never hostile without a warning")
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var guard := _guard(Vector3(0, 0.05, -3), PI, "test.guard", false)
	var a := _person(VILLAGER, Vector3(3, 0.05, -3), "test.villager_a", false)
	var b := _person(VILLAGER, Vector3(-3, 0.05, -3), "test.villager_b", false)
	await step_ticks(3)
	# One blow (one attack instance) that strikes two villagers is one offence.
	var blow := Sim.new_instance_id()
	_blow(a.entity_id, Vector3.ZERO, blow)
	_blow(b.entity_id, Vector3.ZERO, blow)
	await step_ticks(2)
	assert_eq(hits_on(a.entity_id).size() + hits_on(b.entity_id).size(), 2, "both villagers were struck")
	assert_eq(_states("warned").size(), 1, "one warning")
	assert_false(FactionState.is_hostile("village"), "one blow, one offence")
	# 40 s later (the clock of the last offence moved back): a warning again, not hostility.
	FactionState.hub().set_last_offence_tick("village", Sim.tick - 40 * 60)
	_blow(guard.entity_id, Vector3.ZERO)
	await step_ticks(2)
	assert_eq(_states("warned").size(), 2, "a second offence 40 s after the first only warns again")
	assert_false(FactionState.is_hostile("village"), "not hostile")
	assert_eq(guard.entity.team, CombatEntity.Team.NEUTRAL, "the guard stays neutral")
	# A third within 30 s of the second: hostile.
	_blow(guard.entity_id, Vector3.ZERO)
	await step_ticks(2)
	assert_true(FactionState.is_hostile("village"), "the next offence within 30 s turns the village hostile")
	assert_eq(guard.entity.team, CombatEntity.Team.ENEMY, "guard ENEMY")
	var hist := FactionState.hub().history
	assert_eq(hist.size(), 3, "three offences recorded")
	if hist.size() == 3:
		assert_eq([hist[0].result, hist[1].result, hist[2].result], ["warned", "warned", "hostile"], "warned, warned, hostile")


func test_only_the_smashed_barricade_sets_force() -> void:
	spawn_player(Vector3(0, 0.05, 6), 0.0)
	var guard := _guard(Vector3(4, 0.05, -2), PI, "test.guard", false)
	var barricade := (load(BARRICADE) as PackedScene).instantiate() as BreakableProp
	barricade.world_id = "test.village.barricade"
	barricade.position = Vector3(0, 0, -8)
	world.add_child(barricade)
	await step_ticks(3)
	assert_eq(guard.entity.team, CombatEntity.Team.NEUTRAL, "neutral before")
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = "test.village.barricade"
	e.power = 5000.0
	e.attacker_stat = 10.0
	e.attacker_height_m = 5.4864
	e.attacker_growth_stage = 2
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee", "Heavy"])
	e.category = "melee"
	e.attacker_position = Vector3(0, 1, -4)
	Sim.queue_hit(e)
	await step_ticks(3)
	assert_true(barricade.destroyed, "a stage-2 giant smashed the barricade")
	assert_eq(WorldState.get_flag(OUTCOME), "force", "quest.village.outcome = force")
	assert_true(FactionState.is_hostile("village"), "and the village is hostile")
	assert_eq(_states("hostile").size(), 1, "announced once")
	assert_eq(guard.entity.team, CombatEntity.Team.ENEMY, "its guards fight")


func test_attacking_the_village_never_sets_the_outcome() -> void:
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var guard := _guard(Vector3(0, 0.05, -3), PI, "test.guard", false)
	await step_ticks(3)
	_blow(guard.entity_id, Vector3.ZERO)
	await step_ticks(2)
	_blow(guard.entity_id, Vector3.ZERO)
	await step_ticks(2)
	assert_true(FactionState.is_hostile("village"), "two blows: hostile")
	assert_eq(WorldState.get_flag(OUTCOME), null, "no quest.village.outcome")
	assert_true(messages.has([FactionState.text_for("village", "hostile"), "bad"]), "the HUD says so")


# --------------------------------------------------------------------------- the village test level

func test_stand_down_sends_guards_to_their_posts_and_villagers_to_shelter() -> void:
	var level := await _village()
	var guards: Array = level.get_node("Guards").get_children()
	var villagers: Array = []
	for n in level.get_node("Folk").get_children():
		if n is Civilian and (n as Civilian).brain.can_flee():
			villagers.append(n)
	var elder := level.get_node("Folk/Elder") as Civilian
	assert_eq(guards.size(), 2, "two guards")
	assert_eq(villagers.size(), 4, "four villagers")
	var starts := {}
	for v: Civilian in villagers:
		starts[v.entity_id] = v.global_position
		assert_eq(v.brain.state, CivilianBrain.State.IDLE, "%s idles" % v.entity_id)
	var posts := {}
	for g: SoldierEnemy in guards:
		posts[g.entity_id] = g.home_position
		# Pushed off their posts before the news arrives.
		g.global_position = g.home_position + Vector3(-5.0 if g.home_position.x < 0.0 else 5.0, 0, 4.0)
	WorldState.try_set_flag(STOOD_DOWN, true)
	await step_ticks(2)
	assert_eq(_states("stood_down").size(), 1, "faction_changed stood_down")
	for g: SoldierEnemy in guards:
		assert_eq(g.brain.state, EnemyBrain.AIState.STAND_DOWN, "%s stands down" % g.entity_id)
		assert_eq(g.entity.team, CombatEntity.Team.NEUTRAL, "%s stays neutral" % g.entity_id)
	var done: bool = await TestWait.until(self, func() -> bool:
		for v: Civilian in villagers:
			if not v.sheltered:
				return false
		for g: SoldierEnemy in guards:
			if ValleyProbe.flat(g.global_position, posts[g.entity_id]) > EnemyBrain.POST_ARRIVE_M + 0.15:
				return false
		return true, 420)
	assert_true(done, "every guard is back at its post and every villager in shelter")
	for g: SoldierEnemy in guards:
		var post: Node3D = g.formation_marker()
		assert_true(post != null and str(post.get("faction")) == "village", "%s claimed its village post" % g.entity_id)
		assert_true(ValleyProbe.flat(g.global_position, posts[g.entity_id]) <= EnemyBrain.POST_ARRIVE_M + 0.15,
			"%s back at its post" % g.entity_id)
		assert_false(g.is_guarding(), "%s guard down" % g.entity_id)
		assert_false(g.brain.aware, "%s never aware" % g.entity_id)
	var map := level.nav_map()
	for v: Civilian in villagers:
		assert_eq(v.brain.flee_reason, "stood_down", "%s fled when the guards stood down" % v.entity_id)
		assert_true(v.safe_marker != null, "%s chose a shelter" % v.entity_id)
		if v.safe_marker == null:
			continue
		assert_true(str(v.safe_marker.get("marker_id")) != "test.village.safe_yard",
			"%s skipped the walled yard no path reaches" % v.entity_id)
		var path := NavigationServer3D.map_get_path(map, starts[v.entity_id], v.brain.destination, true, 1)
		assert_true(path.size() > 0 and path[path.size() - 1].distance_to(v.brain.destination) <= 1.0,
			"%s's shelter is reachable from where it stood" % v.entity_id)
		assert_true(ValleyProbe.flat(v.global_position, v.safe_marker.global_position) <= 2.0,
			"%s stands at its shelter" % v.entity_id)
		assert_eq(v.process_mode, Node.PROCESS_MODE_DISABLED, "%s stopped processing" % v.entity_id)
		assert_false(v.visible, "%s went inside" % v.entity_id)
		assert_eq(v.brain.picks, 1, "%s chose once (no re-path without a failure)" % v.entity_id)
	var v4 := level.get_node("Folk/Villager4") as Civilian
	assert_true(v4.safe_marker != null and ValleyProbe.flat(starts[v4.entity_id], level.marker("test.village.safe_yard").global_position)
		< ValleyProbe.flat(starts[v4.entity_id], v4.safe_marker.global_position),
		"villager 4 ran past the nearer yard shelter to a reachable one")
	assert_eq(elder.brain.state, CivilianBrain.State.IDLE, "the elder (a talker) stays")
	assert_false(elder.sheltered, "and is not in shelter")


func test_the_elder_is_protected_never_flees_and_talks() -> void:
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var elder := _person(ELDER, Vector3(0, 0.05, -3), "test.elder")
	await step_ticks(3)
	assert_true(elder.is_in_group("npcs") and not elder.is_in_group("civilians"), "an npc, not a civilian who flees")
	assert_false(TargetingRules.player_may_target(elder.entity), "not targetable")
	var talker := elder.get_node_or_null("Talker") as NpcTalker
	assert_true(talker != null, "an NpcTalker")
	if talker != null:
		assert_eq(talker.resolved_npc_id(), "test.elder", "talks as the elder's entity id")
		assert_eq(talker.resolved_dialogue_id(), "dialogue.elder", "runs the npc record's dialogue")
	_blow("test.elder", Vector3.ZERO)
	await step_ticks(2)
	var on := hits_on("test.elder")
	assert_eq(on.size(), 1, "struck once")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.IMMUNE, "protected: IMMUNE")
	assert_true(elder.entity.is_alive(), "unharmed")
	assert_eq(_states("warned").size(), 1, "still an offence: a warning")
	WorldState.try_set_flag(HOSTILE, true)
	await step_ticks(30)
	assert_eq(elder.brain.state, CivilianBrain.State.IDLE, "the elder never flees, even from a hostile village")


func test_members_spawned_after_hostility_spawn_hostile_or_in_shelter() -> void:
	WorldState.set_flag(HOSTILE, true)
	spawn_player(Vector3(0, 0.05, 10), 0.0)
	var shelter := Marker3D.new()
	shelter.position = Vector3(6, 0, -6)
	world.add_child(shelter)
	shelter.add_to_group("safe_markers")
	var guard := _guard(Vector3(0, 0.05, -2), PI, "test.late_guard")
	var v := _person(VILLAGER, Vector3(-4, 0.05, -2), "test.late_villager")
	await step_ticks(1)
	assert_eq(guard.faction_standing, "hostile", "a guard spawned after the news is hostile")
	assert_eq(guard.entity.team, CombatEntity.Team.ENEMY, "team ENEMY from the start")
	var hid: bool = await TestWait.until(self, func() -> bool: return v.sheltered, 30)
	assert_true(hid, "a villager spawned into a hostile village is already in hiding")
	assert_true(ValleyProbe.flat(v.global_position, shelter.global_position) < 0.5, "at its shelter")
	assert_eq(v.process_mode, Node.PROCESS_MODE_DISABLED, "not processing")


## M8 gate fix-up 1 (N4.7, the audit's play pass: nine engine errors at civilian.gd as the giant crossed
## into the Drowned Steps while chunks unloaded): a civilian out of the tree - its chunk unloading, the node
## not freed yet - hears no fight: an attack begun or a blow landed nearby measures nothing from it.
func test_a_civilian_out_of_the_tree_hears_no_fight() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var v := _person(VILLAGER, Vector3(6, 0.05, 0), "test.fixup.villager")
	var s := _guard(Vector3(0, 0.05, 8), 0.0, "test.fixup.guard", false)
	await step_ticks(3)
	assert_true(v._listening(), "in the tree and idle, it listens")
	world.remove_child(v)
	assert_false(v._listening(), "out of the tree it does not")
	Events.ability_started.emit(Sim.tick, s.entity_id, "ability.soldier_chop", Sim.new_instance_id())
	_blow(s.entity_id, p.global_position)
	await step_ticks(2)
	assert_eq(v.brain.state, CivilianBrain.State.IDLE, "and heard nothing (no engine error either)")
	v.free()

