extends IntegrationSuite
## World props (plan §3.8, §4.3): the fortified gate refuses a stage-3 giant with its locked
## message (throttled) and takes no damage; the Deadfall ignores club hits and falls to the tree,
## setting world.forest.deadfall_broken; the barricade opens on its flag without loot or XP and
## loads open, while smashing it sets both village flags; a broken gate opens its nav link (a
## path across shorter than 2 x the direct distance, none before); the cairn falls only to
## projectiles; crates loot once; protected props refuse every hit; the ancient oak, weapon racks
## and item pickups work once per world id through the real interact key; and the sandbox's props.

const FORTIFIED := "res://scenes/world/gate_fortified.tscn"
const PRACTICE := "res://scenes/world/gate_practice.tscn"
const DEADFALL := "res://scenes/world/deadfall.tscn"
const BARRICADE := "res://scenes/world/cart_barricade.tscn"
const CAIRN := "res://scenes/world/cairn.tscn"
const CRATE := "res://scenes/world/crate.tscn"
const OAK := "res://scenes/world/ancient_oak.tscn"
const RACK := "res://scenes/world/weapon_rack.tscn"
const PICKUP := "res://scenes/world/item_pickup.tscn"
const ARENA := "res://scenes/world/sandbox_arena.tscn"
const FORTIFIED_MESSAGE := "Fortified gates can be breached at stage 4."

var messages: Array[String] = []
var xp_requests: Array = []
var opened_events: Array = []
var interactions: Array[String] = []


func before_each() -> void:
	await super()
	messages.clear()
	xp_requests.clear()
	opened_events.clear()
	interactions.clear()
	Events.hud_message.connect(_on_message)
	Events.xp_award_requested.connect(_on_xp)
	Events.object_opened.connect(_on_opened)
	Events.interacted.connect(_on_interacted)


func after_each() -> void:
	for sig: Signal in [Events.hud_message, Events.xp_award_requested, Events.object_opened, Events.interacted]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


func _on_xp(amount: int, source: String) -> void:
	xp_requests.append([amount, source])


func _on_opened(_tick: int, world_id: String, reason: String) -> void:
	opened_events.append([world_id, reason])


func _on_interacted(_tick: int, _actor: String, interact_id: String) -> void:
	interactions.append(interact_id)


func _prop(path: String, pos: Vector3, world_id: String, yaw := 0.0) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.set("world_id", world_id)
	n.position = pos
	n.rotation.y = yaw
	world.add_child(n)
	return n


func _grounded_player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


## A synthetic hit with a chosen attacker growth stage, category and tags.
func _hit(attacker_id: String, target_id: String, at: Vector3, power: float, stage := 1, category := "melee",
		tags := PackedStringArray(["Melee"])) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = attacker_id
	e.target_id = target_id
	e.power = power
	e.attacker_stat = 10.0
	e.attacker_height_m = 1.8
	e.damage_split = {"physical": 1.0}
	e.tags = tags
	e.category = category
	e.attacker_growth_stage = stage
	e.attacker_position = at
	Sim.queue_hit(e)
	await step_ticks(2)


## Starts `attack_id` and waits until the giant is back in LOCOMOTION.
func _attack(p: GiantPlayer, attack_id: String) -> void:
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	assert_eq(p.controller.request(&"attack", {"action_id": attack_id}), CombatController.Verdict.ACCEPT, "%s starts" % attack_id)
	await step_ticks(2)
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 150)
	await step_ticks(1)


# --------------------------------------------------------------------------- gates and obstacles

## The Citadel gate at stage 3: every blow IMMUNE (not permitted: stage), no damage, the locked
## message once per 3 s. With the stage gate lifted, the gate_breach permission still refuses it.
func test_the_fortified_gate_refuses_a_stage_3_giant_with_its_locked_message() -> void:
	var p := await _grounded_player()
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	await step_ticks(2)
	var g := _prop(FORTIFIED, Vector3(0, 0, -3.6), "test.citadel") as BreakableProp
	await step_ticks(2)
	await _attack(p, "ability.heavy_1")
	var on := hits_on("test.citadel")
	assert_true(on.size() >= 1, "the heavy reaches the gate")
	for r in on:
		assert_eq(r.outcome, HitResult.Outcome.IMMUNE, "IMMUNE")
		assert_eq(r.notes, "not_permitted", "not permitted")
		assert_eq(r.health_damage, 0, "no damage")
	assert_eq(g.last_rejection, "stage", "refused for the stage (min 4)")
	assert_near(g.health(), 2000.0, 1e-6, "full health")
	assert_eq(messages.count(FORTIFIED_MESSAGE), 1, "its locked message once (%s)" % [messages])
	await _attack(p, "ability.light_1")
	assert_true(hits_on("test.citadel").size() > on.size(), "a second blow lands within 3 s")
	assert_eq(messages.count(FORTIFIED_MESSAGE), 1, "no second message within 3 s")
	await step_ticks(BreakableProp.LOCKED_MESSAGE_GAP_TICKS)
	await _attack(p, "ability.light_1")
	assert_eq(messages.count(FORTIFIED_MESSAGE), 2, "after 3 s the message shows again")
	assert_eq(g.locked_messages, 2, "two messages in all")
	assert_false(g.destroyed, "still standing")
	TestFixtures.record_override("prop.gate_fortified", {"min_growth_stage": 1})
	var g2 := _prop(FORTIFIED, Vector3(30, 0, -3.6), "test.citadel_2") as BreakableProp
	await step_ticks(2)
	await _hit("player", "test.citadel_2", Vector3(30, 1, 0), 100.0, 3)
	assert_eq(g2.last_rejection, "permission", "a stage-3 profile lacks gate_breach")
	assert_near(g2.health(), 2000.0, 1e-6, "still no damage")


## The Deadfall (TreeWeapon only, stage 3): the club's heavy is refused with its message, the
## tree's blows break it and set world.forest.deadfall_broken.
func test_the_deadfall_ignores_club_hits_and_breaks_with_tree_hits() -> void:
	var p := await _grounded_player()
	p.entity.combatant.unkillable = true
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	await step_ticks(2)
	var d := _prop(DEADFALL, Vector3(0, 0, -3.6), "test.deadfall") as BreakableProp
	await step_ticks(2)
	await _attack(p, "ability.heavy_1")
	var club_hits := hits_on("test.deadfall")
	assert_true(club_hits.size() >= 1, "the club reaches the Deadfall")
	for r in club_hits:
		assert_eq(r.outcome, HitResult.Outcome.IMMUNE, "a club blow is refused")
	assert_eq(d.last_rejection, "tags", "it lacks the TreeWeapon tag")
	assert_near(d.health(), 300.0, 1e-6, "no damage")
	assert_true(messages.has(str(d.record.locked_message)), "the locked message explains it")
	assert_true(p.equipment.grant_weapon("weapon.tree_oak", true).ok, "the tree in hand")
	var blows := 0
	for i in 8:
		if d.destroyed:
			break
		await _attack(p, "ability.tree_heavy" if i % 2 == 0 else "ability.tree_light_1")
		blows += 1
	assert_true(d.destroyed, "the tree breaks the Deadfall (%d blows)" % blows)
	var tree_hits := hits_on("test.deadfall").slice(club_hits.size())
	assert_true(not tree_hits.is_empty() and tree_hits[0].outcome == HitResult.Outcome.HIT, "tree blows land")
	assert_true(tree_hits[0].event.has_tag("TreeWeapon"), "carrying TreeWeapon")
	assert_true(bool(WorldState.get_flag("world.forest.deadfall_broken", false)), "world.forest.deadfall_broken is set")
	assert_true(d.nav_links_enabled(), "its nav link opens the way through")
	assert_false(d.has_collision(), "it no longer blocks")
	assert_eq(destroyed.count("test.deadfall"), 1, "object_destroyed once")


## The cart barricade: the flag faction.village.gate_open opens it (no debris, loot or XP; delta
## opened; object_opened) and it loads open; smashed instead (stage 2), it sets the force outcome
## and village hostility and requests its XP once; a stage-1 blow is refused with its message.
func test_the_barricade_opens_on_its_flag_and_smashing_sets_both_flags() -> void:
	var b := _prop(BARRICADE, Vector3(0, 0, -6), "test.barricade_a") as BreakableProp
	await step_ticks(2)
	assert_true(b.has_collision() and not b.nav_links_enabled(), "a closed barricade blocks")
	WorldState.set_flag("faction.village.gate_open", true)
	assert_true(b.opened and b.destroyed, "the flag opens it")
	assert_eq(opened_events, [["test.barricade_a", "flag"]], "object_opened once")
	assert_true(destroyed.is_empty(), "no object_destroyed")
	assert_true(loot.is_empty() and xp_requests.is_empty(), "no loot or XP")
	assert_false(b.has_collision(), "the way is open")
	assert_true(b.nav_links_enabled(), "its nav link too")
	assert_true(WorldState.is_opened("test.barricade_a"), "the delta says opened")
	assert_false(WorldState.is_destroyed("test.barricade_a"), "not destroyed")
	assert_false(WorldState.has_flag("quest.village.outcome"), "and no outcome flag")
	b.queue_free()
	await step_ticks(2)
	var reloaded := _prop(BARRICADE, Vector3(0, 0, -6), "test.barricade_a") as BreakableProp
	await step_ticks(2)
	assert_true(reloaded.opened and not reloaded.has_collision(), "it loads open")
	assert_eq(opened_events.size(), 1, "silently")
	reloaded.queue_free()
	await step_ticks(2)
	WorldState.clear()
	opened_events.clear()
	var p := await _grounded_player(Vector3(0, 0.05, 6))
	var c := _prop(BARRICADE, Vector3(0, 0, -6), "test.barricade_b") as BreakableProp
	await step_ticks(2)
	await _hit("player", "test.barricade_b", Vector3(0, 1, -3), 100.0, 1)
	assert_eq(c.last_rejection, "stage", "a stage-1 blow is refused")
	assert_true(messages.has(str(c.record.locked_message)), "with the barricade's message")
	await _hit("player", "test.barricade_b", Vector3(0, 1, -3), 400.0, 2)
	assert_true(c.destroyed and not c.opened, "a stage-2 giant smashes it")
	assert_eq(WorldState.get_flag("quest.village.outcome"), "force", "outcome force")
	assert_eq(WorldState.get_flag("faction.village.hostile"), true, "and the village is hostile")
	assert_eq(xp_requests, [[30, "prop:test.barricade_b"]], "its 30 XP once")
	WorldState.set_flag("faction.village.gate_open", true)
	assert_true(opened_events.is_empty(), "the gate_open flag no longer opens a smashed barricade")
	assert_true(WorldState.try_set_flag("quest.village.outcome", "help_cache") == false, "the outcome stays first-write")
	p.queue_free()


## A broken practice gate opens its nav link: with the navmesh split by the gate (two areas, no
## connection where the gate stands, as an offline bake with the gate present leaves it), there is
## no way across before the break, and after it the way across (the link alone; nothing is
## re-baked) is shorter than twice the direct distance. The navmesh is authored, not baked at
## runtime, and set before the region enters the tree: one region update, no async race.
func test_a_broken_gate_opens_its_nav_link() -> void:
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.vertices = PackedVector3Array([
		Vector3(-10, 0, 1.5), Vector3(10, 0, 1.5), Vector3(10, 0, 20), Vector3(-10, 0, 20),
		Vector3(-10, 0, -20), Vector3(10, 0, -20), Vector3(10, 0, -1.5), Vector3(-10, 0, -1.5)])
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nm.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	region.navigation_mesh = nm
	region.position = Vector3(0, 0, 60)
	var g := (load(PRACTICE) as PackedScene).instantiate() as BreakableProp
	g.world_id = "test.nav_gate"
	region.add_child(g)
	var map := world.get_world_3d().navigation_map
	var added_at := NavigationServer3D.map_get_iteration_id(map)
	world.add_child(region)
	await step_ticks(2)
	var from := Vector3(0, 0, 70)
	var to := Vector3(0, 0, 50)
	var direct := from.distance_to(to)
	assert_false(g.nav_links_enabled(), "the intact gate's link is closed")
	var before := await _path_length(map, from, to, added_at, false)
	assert_true(before < 0.0 or before > 2.0 * direct,
		"before the break there is no way across (%.1f m vs %.1f direct)" % [before, direct])
	var intact_at := NavigationServer3D.map_get_iteration_id(map)
	queue_hit("tester", "test.nav_gate", Vector3(0, 1, 64), 1000.0)
	await step_ticks(2)
	assert_true(g.destroyed and g.nav_links_enabled(), "the gate broke and enabled its link")
	var after := await _path_length(map, from, to, intact_at, true)
	assert_true(after > 0.0 and after < 2.0 * direct,
		"after the break the path crosses it (%.1f m < 2 x %.1f)" % [after, direct])
	region.queue_free()
	await step_ticks(2)


## The length of the map's path from `from` to `to`, -1 when it does not reach `to`. P22 (the
## nav-link flake, plan M6-M9 §3.4 design 10): map iterations sync asynchronously, so it waits
## for the map, not for a time - until an iteration later than `since` (the iteration id before
## the change) is published with the region in it (the closest point to `from` is on it); with
## `expect_reach` it keeps waiting while the path does not reach `to` and fewer than two later
## iterations are out (the first may have been built before the link changed). MAX_SYNC_TICKS is
## only a safety net against a map that never synchronizes.
const MAX_SYNC_TICKS := 1200


func _path_length(map: RID, from: Vector3, to: Vector3, since: int, expect_reach: bool) -> float:
	var length := -1.0
	for i in MAX_SYNC_TICKS:
		await step_ticks(1)
		var iteration := NavigationServer3D.map_get_iteration_id(map)
		if iteration <= since or NavigationServer3D.map_get_closest_point(map, from).distance_to(from) > 1.0:
			continue
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		length = -1.0
		if path.size() >= 2 and path[path.size() - 1].distance_to(to) <= 1.0:
			length = 0.0
			for j in range(1, path.size()):
				length += path[j - 1].distance_to(path[j])
		if not expect_reach or length > 0.0 or iteration >= since + 2:
			return length
	return length


## The cairn falls only to the projectile category (Boulder Hurl): a melee blow and a magic bolt are
## refused with its message; it is lockable.
func test_the_cairn_only_falls_to_projectiles() -> void:
	spawn_player(Vector3(0, 0.05, 6))
	var c := _prop(CAIRN, Vector3(0, 0, -3), "test.cairn") as BreakableProp
	await step_ticks(2)
	assert_true(c.entity.is_lockable(), "the cairn is lockable")
	await _hit("player", "test.cairn", Vector3(0, 1, 0), 100.0, 2, "melee")
	assert_eq(c.last_rejection, "category", "a melee blow is refused")
	assert_true(messages.has("Only a hurled boulder can topple the cairn."), "with its message")
	await _hit("player", "test.cairn", Vector3(0, 1, 0), 100.0, 2, "magic", PackedStringArray(["Magic", "Projectile"]))
	assert_eq(c.last_rejection, "category", "so is a magic bolt")
	assert_near(c.health(), 60.0, 1e-6, "no damage")
	await _hit("player", "test.cairn", Vector3(0, 1, 0), 100.0, 2, "projectile", PackedStringArray(["Projectile"]))
	assert_true(c.destroyed, "a projectile-category hit topples it")
	assert_eq(destroyed, ["test.cairn"] as Array[String], "once")


func test_crates_loot_once_and_protected_props_refuse_every_hit() -> void:
	var crate := _prop(CRATE, Vector3(0, 0, -3), "test.crate") as BreakableProp
	await step_ticks(2)
	queue_hit("tester", "test.crate", Vector3(0, 1, 0), 200.0)
	await step_ticks(2)
	assert_true(crate.destroyed, "the crate breaks")
	assert_eq(loot, ["test.crate:item.iron_ingot"] as Array[String], "an iron ingot")
	assert_eq(WorldState.count_of("item.iron_ingot"), 1, "in the inventory")
	crate.queue_free()
	await step_ticks(2)
	var again := _prop(CRATE, Vector3(0, 0, -3), "test.crate") as BreakableProp
	await step_ticks(2)
	assert_true(again.destroyed, "it reloads broken")
	assert_eq(loot.size(), 1, "no second ingot")
	var protected_rec: Dictionary = GameData.get_record("prop.fence_wood").duplicate(true)
	protected_rec["id"] = "prop.test_protected"
	protected_rec["protected"] = true
	TestFixtures.record_override("prop.test_protected", protected_rec)
	spawn_player(Vector3(10, 0.05, 6))
	var f := (load(FENCE) as PackedScene).instantiate() as BreakableProp
	f.world_id = "test.protected_fence"
	(f.get_node("CombatEntity") as CombatEntity).definition_id = "prop.test_protected"
	f.position = Vector3(10, 0, -3)
	world.add_child(f)
	await step_ticks(2)
	await _hit("player", "test.protected_fence", Vector3(10, 1, 0), 400.0, 3)
	assert_eq(f.last_rejection, "protected", "a protected prop refuses the hit")
	assert_eq(hits_on("test.protected_fence").back().outcome, HitResult.Outcome.IMMUNE, "IMMUNE")
	assert_false(f.destroyed, "and stands")
	assert_true(messages.has(BreakableProp.PROTECTED_MESSAGE), "with a message")


# --------------------------------------------------------------------------- interactables

## The ancient oak through the real E key: refused at stage 1 with its message; at stage 3 the
## tree is granted and equipped, the oak's world id is destroyed, world.tree_weapon_taken is set,
## and it disappears; a reload starts it uprooted.
func test_uprooting_the_ancient_oak() -> void:
	var p := await _grounded_player()
	var oak := _prop(OAK, Vector3(0, 0, -4.2), "test.oak") as UprootTree
	await step_ticks(8)
	assert_true(p.interact.current_prompt().begins_with("Uproot"), "the prompt offers it (%s)" % p.interact.current_prompt())
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_false(oak.uprooted, "a stage-1 giant cannot uproot it")
	assert_true(messages.has("Too small to uproot this oak (stage 3)."), "and is told why (%s)" % [messages])
	assert_eq(p.equipment.weapon_id(), "weapon.club", "still the club")
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	await step_ticks(8)
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_true(oak.uprooted, "a stage-3 giant uproots it")
	assert_eq(p.equipment.weapon_id(), "weapon.tree_oak", "and wields the tree")
	assert_true(WorldState.is_destroyed("test.oak"), "the oak's world id is destroyed")
	assert_eq(WorldState.get_flag("world.tree_weapon_taken"), true, "world.tree_weapon_taken")
	assert_false((oak.get_node("Visual") as Node3D).visible, "the oak is gone")
	assert_eq((oak.get_node("Trunk") as CollisionObject3D).collision_layer, 0, "with its collision")
	assert_false(oak.enabled, "and its prompt")
	assert_eq(interactions, ["test.oak"] as Array[String], "Events.interacted once")
	oak.queue_free()
	await step_ticks(2)
	var again := _prop(OAK, Vector3(0, 0, -4.2), "test.oak") as UprootTree
	await step_ticks(2)
	assert_true(again.uprooted and not again.enabled, "a reloaded oak starts uprooted")


## A weapon rack: E mid-swing is refused; E in LOCOMOTION grants and equips once (delta taken) and
## empties the rack; it reloads empty.
func test_weapon_racks_grant_and_equip_once() -> void:
	var p := await _grounded_player()
	var rack := (load(RACK) as PackedScene).instantiate() as WeaponRack
	rack.world_id = "test.rack"
	rack.weapon_id = "weapon.hammer"
	rack.position = Vector3(0, 0, -3.4)
	world.add_child(rack)
	await step_ticks(8)
	assert_true(rack.display_weapon != null and rack.display_weapon.visible, "the maul is on display")
	assert_eq(rack.prompt_text(p), "Take the Raider's Maul", "the prompt names it")
	p.router.inject_light_attack()
	await step_ticks(3)
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_false(rack.taken, "not while swinging")
	assert_true(messages.has("Finish your attack first."), "the reason is shown")
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_true(rack.taken, "taken")
	assert_eq(p.equipment.weapon_id(), "weapon.hammer", "and equipped")
	assert_true(p.equipment.owns("weapon.hammer"), "owned")
	assert_true(ItemPickup.is_taken("test.rack"), "delta taken")
	assert_false(rack.display_weapon.visible, "the rack is empty")
	assert_false(rack.enabled, "no more prompt")
	rack.queue_free()
	await step_ticks(2)
	var again := _prop(RACK, Vector3(0, 0, -3.4), "test.rack") as WeaponRack
	await step_ticks(2)
	assert_true(again.taken and not again.display_weapon.visible, "it reloads empty")


## An item pickup grants its items and flag once, hides itself and reloads hidden.
func test_item_pickups_grant_once_and_set_their_flag() -> void:
	var p := await _grounded_player()
	var pick := (load(PICKUP) as PackedScene).instantiate() as ItemPickup
	pick.world_id = "test.cache"
	pick.item_id = "item.iron_ingot"
	pick.count = 2
	pick.set_flag = "test.p08.cache_taken"
	pick.position = Vector3(0, 0, -3.0)
	world.add_child(pick)
	await step_ticks(8)
	assert_eq(p.interact.current_prompt(), "Take the Iron Ingot (x2)", "the prompt")
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_eq(WorldState.count_of("item.iron_ingot"), 2, "two ingots")
	assert_eq(loot, ["test.cache:item.iron_ingot"] as Array[String], "announced as loot")
	assert_eq(WorldState.get_flag("test.p08.cache_taken"), true, "its flag")
	assert_true(pick.taken and not (pick.get_node("Visual") as Node3D).visible, "it hides")
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_eq(WorldState.count_of("item.iron_ingot"), 2, "a second E gives nothing")
	pick.queue_free()
	await step_ticks(2)
	var again := (load(PICKUP) as PackedScene).instantiate() as ItemPickup
	again.world_id = "test.cache"
	world.add_child(again)
	await step_ticks(2)
	assert_true(again.taken and not again.enabled, "it reloads taken")


## The sandbox gained the practice gate (after the fence, so the soak still breaks the fence
## first), two weapon racks, an ancient oak and two bushes.
func test_the_sandbox_world_props() -> void:
	var arena: Node3D = (load(ARENA) as PackedScene).instantiate()
	TestSpawn.disable_all_ai(arena)
	world.add_child(arena)
	await step_ticks(2)
	var breakables: Array = []
	for n in get_tree().get_nodes_in_group("breakables"):
		if arena.is_ancestor_of(n):
			breakables.append(n)
	assert_eq(breakables.size(), 2, "the fence and the practice gate")
	assert_eq((breakables[0] as BreakableProp).world_id, "sandbox.fence_01", "the fence comes first (the soak's first breakable)")
	var gate := arena.get_node("Navigation/PracticeGate") as BreakableProp
	assert_eq(gate.world_id, "sandbox.gate_01", "the practice gate")
	assert_true(gate.is_structural(), "structural")
	var racks := {}
	for rack_name: String in ["SwordRack", "HammerRack"]:
		var rack := arena.get_node("Navigation/" + rack_name) as WeaponRack
		racks[rack.world_id] = rack.weapon_id
	assert_eq(racks, {"sandbox.sword_rack": "weapon.sword", "sandbox.hammer_rack": "weapon.hammer"}, "two weapon racks")
	assert_eq((arena.get_node("Navigation/AncientOak") as UprootTree).world_id, "sandbox.oak_01", "the ancient oak")
	var bushes := 0
	for n in get_tree().get_nodes_in_group(CosmeticProp.GROUP):
		if arena.is_ancestor_of(n):
			bushes += 1
	assert_eq(bushes, 2, "two bushes")
	var shrine := arena.get_node("Navigation/Shrine") as Node3D
	var pad: Vector3 = shrine.call("growth_pad_position")
	var oak_pos := (arena.get_node("Navigation/AncientOak") as Node3D).global_position
	assert_true(Vector2(oak_pos.x - pad.x, oak_pos.z - pad.z).length() > 10.0, "the oak is clear of the shrine's growth pad")
	arena.queue_free()
	await step_ticks(2)
