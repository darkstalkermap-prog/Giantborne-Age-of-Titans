extends IntegrationSuite
## The Valley's quest line walked through from New Game, once per village outcome (P15, plan
## §3.17, §4.5-4.7, spec §14; slow, runs with --slow). It drives the real systems with direct
## calls - teleports to the objectives, the real dialogue (the elder's talker and
## Quests.dialogue.choose_outcome), shrine.grow, kills applied through synthetic lethal hits,
## props broken by synthetic hits of the right category and tags, interact() on pickups, racks,
## the oak and the forges - and checks for each outcome:
##   * quest.main's sixteen stages complete in order and the slice completes once (the end
##     screen is requested with the outcome);
##   * the XP gates: level 3 before the Grove's growth, level 4 by the end of the gate, level 5
##     before Kingsfall's growth; every reward once (the giant's XP equals the sum of the stage
##     rewards, the outcome's reward, the props' XP and the kills', taken from the world state);
##   * the outcome's lasting effects: Mend at the village for help (2 iron, the village forge
##     open), Roar for intimidate (no iron, the forge cold, the guards stood down), force from the
##     smashed barricade only (the guards turn on the giant, the elder sends it away and the
##     ambush waits in the square on the return leg); the barricade opens for every outcome; the
##     branch quest of the chosen help completes, the other one is never started;
##   * a death and a checkpoint reload mid-run restore the checkpoint (at least 60 % health) and
##     grant nothing twice: the help and force runs die right after the village, the intimidate
##     run dies on the return leg after the boss and growth to stage 3 (the boss checkpoint: the
##     king stays dead, the giant comes back at stage 3 at the Kingsfall shrine).
## The help_cache run also plays the optional Hollow tutorial with the real controls (camera
## toggles, attacks on the dummies, a block and a dodge against the sparring post) through the
## shipped prompts; the other runs leave it, and it is abandoned once the giant grows.
## Spawned enemies outside the village faction get their AI switched off as they spawn (the walk
## is about the quest line, not the fights; P17a's bot plays those), the village's guards and
## people keep theirs, so their standing (neutral, stood down, hostile) plays out for real.

const ELDER := "valley.village.elder"
const KING := "valley.arena.ogre_king"
const MAIN_STAGES := ["leave_hollow", "wolves", "ogre", "grove", "hurl", "to_village", "village", "bridge", "gate",
	"courtyard", "causeway", "boss", "grow3", "tree", "deadfall", "crown"]
const IRON := "item.iron_ingot"
const STAGE1_HEIGHT := 3.6576

var level: LevelRoot
var player: GiantPlayer
var director: EncounterDirector
var main_stages: Array[String] = []
var quest_events: Array = []          ## [event, quest id]
var checkpoints: Array = []           ## [checkpoint id, reason]
var end_requests: Array = []          ## args of ui_screen_requested("end")
var slices := 0
var outcome := ""


func before_each() -> void:
	await super()
	level = null
	player = null
	director = null
	main_stages.clear()
	quest_events.clear()
	checkpoints.clear()
	end_requests.clear()
	slices = 0
	outcome = ""
	Events.quest_stage_changed.connect(_on_stage_changed)
	Events.quest_started.connect(_on_quest_started)
	Events.quest_completed.connect(_on_quest_completed)
	Events.quest_abandoned.connect(_on_quest_abandoned)
	Events.checkpoint_saved.connect(_on_checkpoint_saved)
	Events.ui_screen_requested.connect(_on_screen_requested)
	Events.slice_completed.connect(_on_slice_completed)


func after_each() -> void:
	for sig: Signal in [Events.quest_stage_changed, Events.quest_started, Events.quest_completed,
			Events.quest_abandoned, Events.checkpoint_saved, Events.ui_screen_requested, Events.slice_completed]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _on_stage_changed(_tick: int, quest_id: String, stage_id: String) -> void:
	quest_events.append(["stage", quest_id, stage_id])
	if quest_id == "quest.main":
		var done := Quests.stage_record(Quests.quest_record("quest.main"), stage_id)
		var stages: Array = Quests.quest_record("quest.main").get("stages", [])
		for i in stages.size():
			if str(stages[i].id) == stage_id and i > 0:
				_record_main_stage(str(stages[i - 1].id))
		if done.is_empty():
			fail("unknown main stage %s" % stage_id)


func _record_main_stage(stage_id: String) -> void:
	main_stages.append(stage_id)


func _on_quest_started(_tick: int, quest_id: String) -> void:
	quest_events.append(["started", quest_id, ""])


func _on_quest_completed(_tick: int, quest_id: String) -> void:
	quest_events.append(["completed", quest_id, ""])
	if quest_id == "quest.main":
		_record_main_stage("crown")


func _on_quest_abandoned(_tick: int, quest_id: String) -> void:
	quest_events.append(["abandoned", quest_id, ""])


func _on_checkpoint_saved(_tick: int, checkpoint_id: String, _ok: bool, _message: String) -> void:
	checkpoints.append([checkpoint_id, str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", ""))])


func _on_screen_requested(screen: String, args: Dictionary) -> void:
	if screen == "end":
		end_requests.append(args.duplicate())


func _on_slice_completed(_tick: int) -> void:
	slices += 1


func _quest_event_count(event: String, quest_id: String) -> int:
	return quest_events.filter(func(e: Array) -> bool: return e[0] == event and e[1] == quest_id).size()


# --------------------------------------------------------------------------- the level

## New Game in the Valley (GameSession and the quests in Valley mode), the scene loaded.
func _new_game() -> void:
	GameSession.start_new_valley()
	await _load_level()


## Loads the Valley the way main.gd does after a (re)load: add it, GameSession.on_level_ready
## (a pending restore puts the giant at its respawn point), then wait for the navigation map.
func _load_level() -> void:
	level = ValleyProbe.instance(false)
	world.add_child(level)
	player = level.player()
	player.router.use_injection = true
	director = level.director()
	director.unaware_deactivate_s = 0.25
	director.member_spawned.connect(_on_member_spawned)
	GameSession.on_level_ready(level, player)
	assert_true(await ValleyProbe.wait_for_navigation(self, level), "the Valley's navigation is ready")
	await step_ticks(2)


## Enemies outside the village faction stand still (their AI off); the sparring post, the
## village's guards and its people keep theirs.
func _on_member_spawned(_encounter_id: String, _entity_id: String, node: Node3D) -> void:
	if node is SparringPost or not (node is EnemyActor):
		return
	if str(node.get("faction")) == "":
		(node as EnemyActor).ai_enabled = false


## The death floor and a reload of the last checkpoint, as the death screen's confirm does it.
func _die_and_reload() -> void:
	var killer := HitEvent.new()
	killer.tick = Sim.tick
	killer.instance_id = Sim.new_instance_id()
	killer.attacker_id = "test.walkthrough.doom"
	killer.target_id = player.entity.entity_id
	killer.power = 1.0e6
	killer.damage_split = {"physical": 1.0}
	killer.tags = PackedStringArray(["Melee", "Unblockable"])
	killer.attacker_position = player.global_position + Vector3(0, 0, -2)
	Sim.queue_hit(killer)
	await step_ticks(3)
	assert_eq(player.controller.state, CombatController.State.DEAD, "the giant died")
	Events.reload_checkpoint_requested.emit("death")
	assert_eq(GameSession.scene_reloads.back(), "death", "the death confirm reloads the last checkpoint")
	director.member_spawned.disconnect(_on_member_spawned)
	world.remove_child(level)
	level.free()
	level = null
	await get_tree().process_frame
	await _load_level()


## Puts the giant at `pos` (on the ground) facing `yaw`, runs the director at once and steps.
func _go(pos: Vector3, yaw := 0.0, ticks := 4) -> void:
	GameSession.place_player(player, Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, pos.y + 0.05, pos.z)))
	await step_ticks(1)
	director.update_now()
	await step_ticks(ticks)


func _marker(id: String) -> Vector3:
	var m := level.marker(id)
	assert_true(m != null, "marker %s" % id)
	return m.global_position if m != null else Vector3.ZERO


func _area(id: String) -> Vector3:
	var a := level.area(id)
	assert_true(a != null, "area %s" % id)
	return a.global_position if a != null else Vector3.ZERO


## Waits (at most max_ticks) until quest.main's current stage is `stage_id`.
func _expect_stage(stage_id: String, what: String, max_ticks := 90) -> void:
	await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.main") == stage_id, max_ticks)
	assert_eq(Quests.stage_of("quest.main"), stage_id, "%s: quest.main is at '%s'" % [what, stage_id])


## A synthetic blow from the giant on `target_id` (an actor's or a prop's entity id).
func _strike(target_id: String, power: float, category := "melee", tags := ["Melee"]) -> void:
	var e := Sim.get_entity(target_id)
	assert_true(e != null, "%s is registered" % target_id)
	if e == null:
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = player.entity.entity_id
	h.target_id = target_id
	h.action_id = "ability.light_1"
	h.power = power
	h.attacker_stat = 10.0
	h.attacker_height_m = float(player.profile.get("height_m", STAGE1_HEIGHT))
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(tags)
	h.category = category
	h.attacker_growth_stage = player.current_growth_stage()
	var at: Vector3 = (e.actor as Node3D).global_position if e.actor != null else player.global_position
	h.attacker_position = at + Vector3(0, 1, -2)
	Sim.queue_hit(h)


## Kills every living spawned member of an encounter with synthetic lethal blows; the
## encounter must end cleared.
func _clear_encounter(encounter_id: String) -> void:
	if director.encounter_state(encounter_id) == EncounterDirector.DORMANT:
		director.force_activate(encounter_id)
		director.update_now()
	var members := director.members_of(encounter_id)
	assert_true(members.size() > 0, "%s has members" % encounter_id)
	for id in members:
		var n := director.spawned(id)
		var e := Sim.get_entity(id)
		if n != null and e != null and e.is_alive():
			_strike(id, 1.0e6)
	await TestWait.until(self, func() -> bool:
		return director.encounter_state(encounter_id) == EncounterDirector.CLEARED, 30)
	assert_eq(director.encounter_state(encounter_id), EncounterDirector.CLEARED, "%s cleared" % encounter_id)


## Ends the giant's combat timer (the growth and loadout gates wait 10 s after the last blow).
func _out_of_combat() -> void:
	player.entity.combatant.pools.since_combat = 999.0


func _prop(world_id: String) -> Node3D:
	var n := ValleyProbe.prop(level, world_id)
	assert_true(n != null, "prop %s" % world_id)
	return n


func _shrine(world_id: String) -> Shrine:
	var s := ValleyProbe.shrine(level, world_id)
	assert_true(s != null, "shrine %s" % world_id)
	return s


## Visits a shrine (its first activation per load is a free Rest and a checkpoint).
func _visit_shrine(world_id: String) -> void:
	var s := _shrine(world_id)
	await _go(s.get_node("SpawnPoint").global_position, s.rotation.y)
	await TestWait.until(self, func() -> bool: return s.is_activated(), 30)
	assert_true(s.is_activated(), "%s activated" % world_id)
	await TestWait.until(self, func() -> bool: return GameSession.respawn_id == world_id, 30)
	assert_eq(GameSession.respawn_id, world_id, "%s is the respawn point" % world_id)


func _grow_at(world_id: String, stage: int) -> void:
	var s := _shrine(world_id)
	await _go(s.growth_pad_position(), s.rotation.y, 6)
	_out_of_combat()
	var r := s.grow(player, stage)
	assert_true(bool(r.get("ok", false)), "grown to stage %d at %s (%s)" % [stage, world_id, r])
	await step_ticks(3)
	assert_eq(player.current_growth_stage(), stage, "stage %d" % stage)


## The elder's conversation through her talker (as E does), returning the running session.
func _talk_to_elder() -> DialogueSession:
	var elder := director.spawned(ELDER)
	assert_true(elder != null, "Elder Maren is in the village")
	if elder == null:
		return null
	await _go(elder.global_position + Vector3(0, 0, 3.0), 0.0, 2)
	var talker := elder.get_node_or_null("Talker") as NpcTalker
	assert_true(talker != null and talker.can_interact(player), "she can be talked to")
	if talker == null:
		return null
	talker.interact(player)
	await step_ticks(1)
	assert_true(Quests.dialogue != null and Quests.dialogue.is_active(), "the elder's conversation runs")
	return Quests.dialogue


func _end_talk() -> void:
	if Quests.dialogue != null:
		Quests.end_dialogue()
	await step_ticks(2)


func _iron() -> int:
	return WorldState.count_of(IRON)


## The XP the world state accounts for: every quest stage rewarded (its once-flag), the village
## reward, the props broken with an xp_reward and every kill recorded. The giant's XP must equal
## it exactly: a reward granted twice would show.
func _accounted_xp() -> int:
	var total := 0
	for rec: Dictionary in GameData.records_of_type("quest"):
		for s: Dictionary in rec.get("stages", []):
			if WorldState.has_flag(Quests.reward_flag(str(rec.id), str(s.id))):
				total += int(s.get("xp", 0))
	if WorldState.has_flag("reward.village.help"):
		total += 120
	if WorldState.has_flag("reward.village.intimidate"):
		total += 40
	for id: String in WorldState.deltas:
		var d: Dictionary = WorldState.deltas[id]
		if bool(d.get("killed", false)):
			total += _kill_xp(id)
		if bool(d.get("destroyed", false)):
			total += _prop_xp(id)
	return total


static func _kill_xp(entity_id: String) -> int:
	for rec: Dictionary in GameData.records_of_type("encounter"):
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.entity_id) == entity_id:
				return int(GameData.get_record(str(sp.definition)).get("xp_reward", 0))
	return 0


func _prop_xp(world_id: String) -> int:
	var n := ValleyProbe.prop(level, world_id) if level != null else null
	if n == null or not ("record" in n):
		return 0
	var rec: Variant = n.get("record")
	return int((rec as Dictionary).get("xp_reward", 0)) if typeof(rec) == TYPE_DICTIONARY else 0


func _assert_xp_accounted(what: String) -> void:
	assert_eq(int(player.progression.xp), _accounted_xp(), "%s: the giant's XP is every reward once" % what)


# --------------------------------------------------------------------------- the line

## The Hollow's optional tutorial, played with the real controls through the shipped prompts.
func _hollow_tutorial() -> void:
	assert_eq(Quests.stage_of("quest.tutorial"), "awaken", "the tutorial starts with New Game")
	await TestWait.until(self, func() -> bool: return str(Quests.current_tutorial().get("id", "")) == "tutorial.camera", 30)
	assert_eq(str(Quests.current_tutorial().get("id", "")), "tutorial.camera", "the camera prompt shows at the Cradle")
	for i in 2:
		player.router.inject_edge(&"camera_toggle")
		await step_ticks(4)
	assert_eq(WorldState.get_flag("tutorial.camera.done"), true, "two camera toggles teach it")
	await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.tutorial") == "train", 30)
	assert_eq(Quests.stage_of("quest.tutorial"), "train", "awaken done")
	# The dummies: three lights, a heavy and Heavy Footfall on dummy 1, then a lock.
	var dummy := level.get_node("Dummies/valley_hollow_dummy_1") as Node3D
	var front := dummy.global_position + Vector3(2.8, 0, 0)
	await _go(front, PI * 0.5, 6)
	player.camera_rig.yaw = player.facing_yaw
	await TestWait.until(self, func() -> bool: return str(Quests.current_tutorial().get("id", "")) == "tutorial.light", 30)
	assert_eq(str(Quests.current_tutorial().get("id", "")), "tutorial.light", "the light prompt at the dummies")
	for edge: StringName in [&"light", &"light", &"light"]:
		player.router.inject_edge(edge)
		await step_ticks(26)
	await step_ticks(30)
	assert_eq(WorldState.get_flag("tutorial.light.done"), true, "three lights teach it")
	await TestWait.until(self, func() -> bool: return str(Quests.current_tutorial().get("id", "")) == "tutorial.heavy", 30)
	player.router.inject_edge(&"heavy")
	await step_ticks(90)
	assert_eq(WorldState.get_flag("tutorial.heavy.done"), true, "a heavy teaches the heavy")
	await TestWait.until(self, func() -> bool: return str(Quests.current_tutorial().get("id", "")) == "tutorial.footfall", 30)
	player.router.inject_edge(&"slot_1")
	await step_ticks(70)
	assert_eq(WorldState.get_flag("tutorial.footfall.done"), true, "Heavy Footfall teaches itself")
	await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.tutorial") == "spar", 30)
	assert_eq(Quests.stage_of("quest.tutorial"), "spar", "the dummies took light x3, a heavy and Footfall")
	await TestWait.until(self, func() -> bool: return str(Quests.current_tutorial().get("id", "")) == "tutorial.lock", 30)
	player.router.inject_edge(&"lock_press")
	await step_ticks(6)
	assert_eq(WorldState.get_flag("tutorial.lock.done"), true, "locking on teaches the lock")
	player.router.inject_edge(&"lock_press")
	await step_ticks(4)
	# The sparring post: a held block, then a roll through the swing.
	var post := director.spawned("valley.hollow.sparring_post") as SparringPost
	assert_true(post != null, "the Hollow's sparring post is up")
	if post == null:
		return
	var at := post.global_position + Vector3(0, 0, 3.2)
	await _go(at, 0.0, 2)
	player.camera_rig.yaw = 0.0
	var blocked: bool = await TestWait.until(self, func() -> bool:
		if str(Quests.current_tutorial().get("id", "")) == "tutorial.block" \
				and post.controller.state == CombatController.State.ATTACKING:
			player.router.set_injected_hold(&"block", true)
			player.router.inject_edge(&"block_press")
		return WorldState.get_flag("tutorial.block.done") == true, 600)
	player.router.set_injected_hold(&"block", false)
	player.router.inject_edge(&"block_release")
	assert_true(blocked, "a block against the post teaches blocking")
	await step_ticks(20)
	# The roll's invulnerability runs from 0.10 s to 0.30 s into it (action.dodge): roll 10 ticks
	# before the swing lands.
	var dodged: bool = await TestWait.until(self, func() -> bool:
		if str(Quests.current_tutorial().get("id", "")) == "tutorial.dodge" and _post_strikes_in(post) == 10:
			player.router.set_injected_move(Vector2(0, 1))
			player.router.inject_edge(&"dodge")
		return WorldState.get_flag("tutorial.dodge.done") == true, 900)
	player.router.set_injected_move(Vector2.ZERO)
	assert_true(dodged, "a roll through the swing teaches the dodge")
	await TestWait.until(self, func() -> bool: return Quests.is_complete("quest.tutorial"), 30)
	assert_true(Quests.is_complete("quest.tutorial"), "the Hollow's tutorial is complete")
	await _go(at + Vector3(0, 0, 8), 0.0, 2)


## Ticks until the post's current swing becomes active (99 when it is not winding up).
func _post_strikes_in(post: SparringPost) -> int:
	var c := post.controller
	if c.action == null or c.phase() != ActionDef.Phase.WINDUP:
		return 99
	return c.action.windup_ticks - c.elapsed


## Giant's Hollow to the Grove: the trail, wolves A and the forest waystone, the hunters, the
## forest ogre, growth to stage 2 and the cairn.
func _forest_to_the_grove() -> void:
	await _go(_area("valley.area.forest_edge"), PI)
	await _expect_stage("wolves", "the trail leads into the Old Wood")
	await _go(_marker("valley.marker.wolves_a") + Vector3(0, 0, 14), PI)
	await _clear_encounter("encounter.forest_wolves_a")
	await _expect_stage("ogre", "the wolf pack is beaten")
	var way := level.checkpoint("valley.cp.forest_road") as Waystone
	await _go(way.global_position, way.rotation.y)
	await TestWait.until(self, func() -> bool: return GameSession.respawn_id == "valley.cp.forest_road", 30)
	assert_eq(GameSession.respawn_id, "valley.cp.forest_road", "the forest waystone is the respawn point")
	await _go(_marker("valley.marker.hunters") + Vector3(0, 0, 12), PI)
	await _clear_encounter("encounter.forest_hunters")
	await _go(_marker("valley.marker.ogre_clearing") + Vector3(-8, 0, 12), PI)
	await _clear_encounter("encounter.forest_ogre")
	await _expect_stage("grove", "the forest ogre is dead")
	assert_true(int(player.progression.level) >= 3, "level 3 before the Grove's growth (level %d, %d XP)" % [
		player.progression.level, player.progression.xp])
	await _visit_shrine("valley.shrine.grove")
	await _grow_at("valley.shrine.grove", 2)
	await _expect_stage("hurl", "grown to stage 2")
	assert_true(player.known_abilities.has("ability.boulder_hurl"), "the growth teaches Boulder Hurl")
	assert_true(player.known_abilities.has("ability.runic_bolt"), "level 3 teaches Runic Bolt")
	# The cairn takes only a hurled boulder (the projectile category): a blow does nothing.
	var cairn := _prop("valley.grove.cairn") as BreakableProp
	_strike("valley.grove.cairn", 1.0e6, "melee", ["Melee"])
	await step_ticks(3)
	assert_false(cairn.destroyed, "a club blow does not topple the cairn")
	_strike("valley.grove.cairn", 1.0e6, "projectile", ["Ability", "Projectile", "Ranged"])
	await step_ticks(3)
	assert_true(cairn.destroyed, "a boulder topples it")
	await _expect_stage("to_village", "the cairn is down")


## The King's Road to Thornwick: the road patrol (the first mage), the west gate and the
## Thornwick shrine.
func _road_to_thornwick() -> void:
	await _go(_marker("valley.marker.road_line_1") + Vector3(-10, 0, -8), -PI * 0.4)
	assert_eq(director.encounter_state("encounter.road_patrol"), EncounterDirector.ACTIVE, "the road patrol waits on the King's Road")
	await _clear_encounter("encounter.road_patrol")
	await _go(_area("valley.area.village"), -PI * 0.5)
	await _expect_stage("village", "through Thornwick's west gate")
	await _visit_shrine("valley.shrine.thornwick")


## Snapshot of what a death must not change twice.
func _snapshot() -> Dictionary:
	var rewards := {}
	for f: String in WorldState.flags:
		if f.begins_with("reward."):
			rewards[f] = WorldState.flags[f]
	return {"xp": int(player.progression.xp), "level": int(player.progression.level), "iron": _iron(),
		"items": WorldState.inventory.duplicate(), "rewards": rewards, "known": player.known_abilities.duplicate(),
		"outcome": str(WorldState.get_flag("quest.village.outcome", "")), "stage": Quests.stage_of("quest.main")}


## Waits for the pending checkpoint, dies, reloads, and checks the checkpoint came back exactly
## (with the death floor) and nothing is granted twice.
func _death_and_reload(what: String, respawn: String) -> void:
	await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 120)
	assert_true(GameSession.pending_checkpoint().is_empty(), "%s: the checkpoint was taken (blockers %s)" % [what,
		GameSession.checkpoint_blockers()])
	var snap := _snapshot()
	var deaths := int(GameSession.stats.deaths)
	await _die_and_reload()
	assert_eq(int(GameSession.stats.deaths), deaths + 1, "%s: the death is counted" % what)
	var spawn := GameSession.find_checkpoint(respawn)
	assert_true(spawn != null and ValleyProbe.flat(player.global_position, spawn.global_position) < 0.1,
		"%s: back at %s" % [what, respawn])
	var pools := player.entity.combatant.pools
	assert_true(player.entity.is_alive() and pools.health >= pools.health_max * 0.6 - 0.01,
		"%s: alive with at least 60 %% health (%.0f / %.0f)" % [what, pools.health, pools.health_max])
	var now := _snapshot()
	for key: String in snap:
		assert_eq(now[key], snap[key], "%s: %s as at the checkpoint" % [what, key])
	_assert_xp_accounted(what + " after the reload")


## The bridge, the practice gate, the courtyard, the armory and the causeway.
func _bridge_to_the_causeway() -> void:
	var barricade := _prop("valley.village.barricade") as BreakableProp
	assert_true(barricade.destroyed or barricade.opened, "the barricade is open (%s)" % outcome)
	assert_false(barricade.has_collision(), "nothing blocks the bridge")
	await _go(_area("valley.area.ruins_approach"), -PI * 0.5)
	await _expect_stage("gate", "over the King's Bridge")
	await _clear_encounter("encounter.ruins_gate")
	var gate := _prop("valley.ruins.practice_gate") as BreakableProp
	_strike("valley.ruins.practice_gate", 150.0 / (1.15 * 100.0 / 110.0))
	await step_ticks(3)
	assert_eq(gate.stage_id(), "cracked", "the practice gate cracks")
	assert_true(gate.has_collision(), "and still holds")
	_strike("valley.ruins.practice_gate", 1.0e6)
	await step_ticks(3)
	assert_true(gate.destroyed and not gate.has_collision(), "then breaks")
	await _expect_stage("courtyard", "the practice gate is broken")
	assert_true(int(player.progression.level) >= 4, "level 4 by the end of the gate (level %d, %d XP)" % [
		player.progression.level, player.progression.xp])
	var way := level.checkpoint("valley.cp.ruins_gate") as Waystone
	await _go(way.global_position, way.rotation.y)
	await TestWait.until(self, func() -> bool: return GameSession.respawn_id == "valley.cp.ruins_gate", 30)
	assert_eq(GameSession.respawn_id, "valley.cp.ruins_gate", "the ruins waystone opens with the gate")
	await _go(_marker("valley.marker.ruins_courtyard"), PI * 0.6)
	await _clear_encounter("encounter.ruins_courtyard")
	await _expect_stage("causeway", "the courtyard's garrison is broken")
	# The armory: its crate holds one of the Valley's five iron ingots.
	var iron := _iron()
	await _go(Vector3(176, 0, -94), PI)
	_strike("valley.ruins.armory_crate", 1.0e6)
	await step_ticks(3)
	assert_eq(_iron(), iron + 1, "the armory crate gives an iron ingot")
	await _go(_area("valley.area.causeway"), PI)
	await _expect_stage("boss", "the Kings' Causeway")


## Kingsfall: the shrine, the Ogre King, growth to stage 3 and the oak.
func _kingsfall() -> void:
	await _visit_shrine("valley.shrine.kingsfall")
	var kingsfall := _shrine("valley.shrine.kingsfall")
	assert_eq(str(kingsfall.can_grow(player, 3).get("reason", "")), "flags", "the shrine will not grow the giant while the king lives")
	await _go(Vector3(150, 0, 112), PI, 4)
	var arena := level.get_node("Kingsfall/BossArena") as BossArena
	arena.engage()
	await step_ticks(2)
	assert_true(arena.is_engaged(), "the arena engages")
	var iron := _iron()
	_strike(KING, 1.0e7)
	await step_ticks(4)
	assert_true(arena.is_defeated(), "the Ogre King falls")
	assert_eq(WorldState.get_flag("world.ogre_king.defeated"), true, "world.ogre_king.defeated")
	assert_eq(_iron(), iron + 1, "he drops an iron ingot")
	await _expect_stage("grow3", "the Ogre King is dead")
	await TestWait.until(self, func() -> bool: return GameSession.respawn_id == "valley.shrine.kingsfall", 60)
	assert_eq(GameSession.respawn_id, "valley.shrine.kingsfall", "the boss's checkpoint respawns at Kingsfall")
	assert_true(int(player.progression.level) >= 5, "level 5 before Kingsfall's growth (level %d, %d XP)" % [
		player.progression.level, player.progression.xp])
	await _grow_at("valley.shrine.kingsfall", 3)
	await _expect_stage("tree", "grown to stage 3")
	var oak := _prop("valley.kingsfall.oak") as UprootTree
	await _go(oak.global_position + Vector3(0, 0, -6), PI)
	assert_true(oak.can_interact(player), "a stage-3 giant can uproot the oak")
	oak.interact(player)
	await step_ticks(2)
	assert_eq(player.equipment.weapon_id(), "weapon.tree_oak", "and wields it")
	await _expect_stage("deadfall", "the oak is uprooted")


## Reforges `base` at the Giantforge (equipping it first), then takes the tree back up.
func _giantforge(base: String) -> void:
	var forge := _prop("valley.ruins.giantforge") as Forge
	await _go(forge.global_position + Vector3(0, 0, 5), 0.0)
	var iron := _iron()
	assert_true(iron >= 2, "two iron ingots for the Giantforge (%d)" % iron)
	assert_true(bool(player.equipment.equip_weapon(base).get("ok", false)), "%s in hand" % base)
	await step_ticks(2)
	var r := forge.upgrade(player)
	assert_true(bool(r.get("ok", false)), "the Giantforge reforges %s (%s)" % [base, r])
	assert_eq(_iron(), iron - 2, "for two iron")
	assert_true(bool(player.equipment.equip_weapon("weapon.tree_oak").get("ok", false)), "the tree back in hand")
	await step_ticks(2)


## The return leg: the bridge's patrol, the ambush when hostile, the Deadfall, the wardens and
## the crown.
func _return_leg() -> void:
	await _go(_marker("valley.marker.practice_gate") + Vector3(4, 0, 0), PI * 0.5)
	assert_eq(director.encounter_state("encounter.return_patrol"), EncounterDirector.ACTIVE,
		"the return patrol holds the bridge once the king has fallen")
	await _clear_encounter("encounter.return_patrol")
	await _go(Vector3(62, 0, -20), PI * 0.5)
	if outcome == "force":
		assert_eq(director.encounter_state("encounter.village_ambush"), EncounterDirector.ACTIVE,
			"force: the ambush waits in the square")
		await _clear_encounter("encounter.village_ambush")
	else:
		assert_eq(director.encounter_state("encounter.village_ambush"), EncounterDirector.DORMANT,
			"%s: no ambush" % outcome)
	var deadfall := _prop("valley.forest.deadfall") as BreakableProp
	await _go(_marker("valley.marker.deadfall"), 0.0)
	_strike("valley.forest.deadfall", 1.0e6, "melee", ["Melee", "BasicAttack"])
	await step_ticks(3)
	assert_false(deadfall.destroyed, "the Deadfall shrugs off a blow without the tree")
	_strike("valley.forest.deadfall", 1.0e6, "melee", ["Melee", "BasicAttack", "TreeWeapon"])
	await step_ticks(3)
	assert_true(deadfall.destroyed, "the tree smashes the Deadfall")
	await _expect_stage("crown", "the Deadfall is smashed")
	var way := level.checkpoint("valley.cp.barrow_gap") as Waystone
	await _go(way.global_position, way.rotation.y)
	await TestWait.until(self, func() -> bool: return GameSession.respawn_id == "valley.cp.barrow_gap", 30)
	assert_eq(GameSession.respawn_id, "valley.cp.barrow_gap", "the Barrow waystone opens behind the Deadfall")
	await _go(_marker("valley.marker.crown") + Vector3(0, 0, 14), 0.0)
	await _clear_encounter("encounter.barrow_wardens")
	var crown := _prop("valley.barrow.crown") as ItemPickup
	await _go(crown.global_position + Vector3(0, 0, 3), 0.0)
	crown.interact(player)
	await step_ticks(3)
	crown.interact(player)
	await step_ticks(3)
	assert_eq(WorldState.count_of("item.crown_first_king"), 1, "the crown, once")
	await TestWait.until(self, func() -> bool: return Quests.is_complete("quest.main"), 60)
	assert_true(Quests.is_complete("quest.main"), "the Valley of Broken Kings is complete")


## The common end of every run.
func _assert_the_end(expected_outcome: String) -> void:
	assert_eq(main_stages, _typed(MAIN_STAGES), "every main stage, in order")
	assert_eq(WorldState.get_flag("slice.completed"), true, "slice.completed")
	assert_eq(slices, 1, "slice_completed once")
	assert_eq(end_requests.size(), 1, "the end screen is requested once")
	if not end_requests.is_empty():
		assert_eq(str(end_requests[0].get("outcome", "")), expected_outcome, "the end screen names the outcome")
	assert_eq(str(WorldState.get_flag("quest.village.outcome", "")), expected_outcome, "the village outcome")
	for s: String in MAIN_STAGES:
		assert_eq(WorldState.get_flag("reward.main." + s), true, "reward.main.%s" % s)
	assert_eq(_quest_event_count("completed", "quest.main"), 1, "quest.main completes once")
	_assert_xp_accounted("the end")
	var main_checkpoints := checkpoints.filter(func(c: Array) -> bool: return c[1] == "quest_stage" or c[1] == "quest_complete")
	assert_true(main_checkpoints.size() >= 8, "checkpoints along the line (%d after main stages)" % main_checkpoints.size())


static func _typed(a: Array) -> Array[String]:
	var out: Array[String] = []
	for s: Variant in a:
		out.append(str(s))
	return out


# --------------------------------------------------------------------------- the four outcomes

func test_help_cache_the_stolen_supplies() -> void:
	outcome = "help_cache"
	await _new_game()
	await _hollow_tutorial()
	await _forest_to_the_grove()
	await _road_to_thornwick()
	var s := await _talk_to_elder()
	if s == null:
		return
	assert_eq(s.node_id, "greet", "she greets the giant")
	assert_true(s.find_choice("intimidate") >= 0, "a stage-2 giant may loom over her")
	assert_true(bool(s.choose_outcome("offer_cache").ok), "the giant offers to bring back the cache")
	await _end_talk()
	assert_eq(str(WorldState.get_flag("quest.village.offer", "")), "cache", "the offer is the cache")
	await TestWait.until(self, func() -> bool: return Quests.quest_state("quest.village_cache") == Quests.ACTIVE, 30)
	assert_eq(Quests.stage_of("quest.village_cache"), "get_cache", "the cache quest starts")
	# The quarry: the raiders, their chest (iron) and the cache.
	await _go(_marker("valley.marker.quarry_cache") + Vector3(0, 0, 12), PI)
	await _clear_encounter("encounter.quarry_raiders")
	assert_true(WorldState.count_of("item.wood_scrap") >= 4, "the raiders carried wood scrap (%d)" % WorldState.count_of("item.wood_scrap"))
	_strike("valley.quarry.chest", 1.0e6)
	await step_ticks(3)
	assert_eq(_iron(), 1, "the quarry chest holds an iron ingot")
	var cache := _prop("valley.quarry.cache") as ItemPickup
	cache.interact(player)
	await step_ticks(3)
	assert_eq(WorldState.count_of("item.supply_cache"), 1, "the supply cache")
	await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.village_cache") == "return_cache", 30)
	assert_eq(Quests.stage_of("quest.village_cache"), "return_cache", "now bring it back")
	s = await _talk_to_elder()
	if s == null:
		return
	assert_eq(s.node_id, "report_cache", "she sees the cache")
	var xp := int(player.progression.xp)
	var r := s.choose_outcome("help_cache")
	assert_true(bool(r.ok) and bool(r.granted), "the cache is handed over and rewarded")
	await _end_talk()
	assert_eq(int(player.progression.xp), xp + 120, "120 XP")
	assert_eq(WorldState.count_of("item.supply_cache"), 0, "the cache is hers again")
	assert_eq(_iron(), 3, "2 iron from Thornwick (and the chest's)")
	assert_true(player.known_abilities.has("ability.ancestral_mend"), "Ancestral Mend learned at the village")
	await _village_settled("help_cache")
	await _death_and_reload("help_cache", "valley.shrine.thornwick")
	s = await _talk_to_elder()
	if s != null:
		assert_eq(s.node_id, "done_help", "after the reload she remembers the help")
		await _end_talk()
	_assert_xp_accounted("a second talk")
	# The village smithy reforges the club at once.
	await _village_forge(3)
	await _bridge_to_the_causeway()
	await _kingsfall()
	await _return_leg()
	await _assert_the_end("help_cache")
	assert_eq(Quests.quest_state("quest.village_cache"), Quests.COMPLETED, "the cache quest is complete")
	assert_eq(Quests.quest_state("quest.village_ogre"), Quests.INACTIVE, "the ogre quest never started")
	assert_eq(Quests.quest_state("quest.tutorial"), Quests.COMPLETED, "the tutorial stays complete")
	assert_false(WorldState.has_flag("reward.village.intimidate"), "no intimidation reward")


## The village forge: open for a helper, it reforges the club for two of `iron` ingots.
func _village_forge(iron: int) -> void:
	var forge := _prop("valley.village.forge") as Forge
	assert_true(forge.is_open(), "the village forge works for a helper")
	await _go(forge.global_position + Vector3(5, 0, 0), PI * 0.5)
	assert_eq(_iron(), iron, "%d iron at the smithy" % iron)
	var up := forge.upgrade(player)
	assert_true(bool(up.ok), "the village forge reforges the club (%s)" % up)
	assert_eq(player.equipment.weapon_id(), "weapon.club_reinforced", "the reinforced club")
	assert_eq(_iron(), iron - 2, "for two ingots")


## After an outcome: quest.village is resolved, the main quest moved on to the bridge and the
## barricade opened (for every outcome).
func _village_settled(expected: String) -> void:
	await _expect_stage("bridge", "Thornwick is settled (%s)" % expected)
	assert_eq(str(WorldState.get_flag("quest.village.outcome", "")), expected, "outcome %s" % expected)
	assert_eq(Quests.quest_state("quest.village"), Quests.COMPLETED, "quest.village ends on the outcome")
	var barricade := _prop("valley.village.barricade") as BreakableProp
	assert_true(barricade.destroyed or barricade.opened, "the barricade is open")
	await TestWait.until(self, func() -> bool: return barricade.nav_links_enabled(), 10)
	assert_true(barricade.nav_links_enabled(), "its nav links open the road to the bridge")


func test_help_ogre_the_field_ogre() -> void:
	outcome = "help_ogre"
	await _new_game()
	await _forest_to_the_grove()
	assert_eq(_quest_event_count("abandoned", "quest.tutorial"), 1, "the unfinished Hollow tutorial ends with the growth")
	await _road_to_thornwick()
	var s := await _talk_to_elder()
	if s == null:
		return
	assert_eq(s.node_id, "greet", "she greets the giant")
	assert_true(bool(s.choose_outcome("offer_ogre").ok), "the giant offers to drive off the ogre")
	await _end_talk()
	assert_eq(str(WorldState.get_flag("quest.village.offer", "")), "ogre", "the offer is the ogre")
	await TestWait.until(self, func() -> bool: return Quests.quest_state("quest.village_ogre") == Quests.ACTIVE, 30)
	assert_eq(Quests.stage_of("quest.village_ogre"), "kill_field_ogre", "the ogre quest starts")
	assert_eq(Quests.current_objective().get("quest_id", ""), "quest.main", "the tracker leads with the main quest")
	assert_eq(str((Quests.objectives()[1] as Dictionary).get("quest_id", "")), "quest.village_ogre",
		"and shows the branch before quest.village")
	s = await _talk_to_elder()
	if s != null:
		assert_eq(s.node_id, "waiting_ogre", "she waits for the news")
		await _end_talk()
	await _go(_marker("valley.marker.field_ogre") + Vector3(0, 0, -14), 0.0)
	await _clear_encounter("encounter.field_ogre")
	await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.village_ogre") == "report", 30)
	assert_eq(Quests.stage_of("quest.village_ogre"), "report", "the ogre is gone: tell her")
	s = await _talk_to_elder()
	if s == null:
		return
	assert_eq(s.node_id, "report_ogre", "she has heard the fields are quiet")
	var xp := int(player.progression.xp)
	var r := s.choose_outcome("help_ogre")
	assert_true(bool(r.ok) and bool(r.granted), "the help is rewarded")
	await _end_talk()
	assert_eq(int(player.progression.xp), xp + 120, "120 XP")
	assert_eq(_iron(), 2, "2 iron from Thornwick")
	assert_true(player.known_abilities.has("ability.ancestral_mend"), "Ancestral Mend learned at the village")
	await _village_settled("help_ogre")
	await _death_and_reload("help_ogre", "valley.shrine.thornwick")
	s = await _talk_to_elder()
	if s != null:
		assert_eq(s.node_id, "done_help", "after the reload she remembers the help")
		await _end_talk()
	_assert_xp_accounted("a second talk")
	await _village_forge(2)
	await _bridge_to_the_causeway()
	await _kingsfall()
	await _return_leg()
	await _assert_the_end("help_ogre")
	assert_eq(Quests.quest_state("quest.village_ogre"), Quests.COMPLETED, "the ogre quest is complete")
	assert_eq(Quests.quest_state("quest.village_cache"), Quests.INACTIVE, "the cache quest never started")
	assert_eq(Quests.quest_state("quest.tutorial"), Quests.ABANDONED, "the tutorial stays abandoned")


func test_intimidate_and_the_boss_checkpoint() -> void:
	outcome = "intimidate"
	await _new_game()
	await _forest_to_the_grove()
	await _road_to_thornwick()
	var s := await _talk_to_elder()
	if s == null:
		return
	assert_true(s.find_choice("intimidate") >= 0, "a stage-2 giant may loom over her")
	var xp := int(player.progression.xp)
	var level_before := int(player.progression.level)
	var r := s.choose_outcome("intimidate")
	assert_true(bool(r.ok) and bool(r.granted), "intimidation is rewarded")
	assert_eq(s.node_id, "cowed", "she gives in")
	await _end_talk()
	assert_eq(int(player.progression.xp), xp + 40, "40 XP")
	assert_true(player.known_abilities.has("ability.thunder_roar"), "Thunder Roar learned at the village")
	if level_before < 4 and int(player.progression.level) < 4:
		assert_true(player.controller.level_exempt.has("ability.thunder_roar"), "taught early: usable below level 4")
		assert_false(player.known_abilities.has("ability.ancestral_mend"), "no Mend for an intimidator")
	assert_eq(_iron(), 0, "no iron from Thornwick")
	await _village_settled("intimidate")
	assert_eq(FactionState.standing("village"), "stood_down", "the village stands down")
	var guard := director.spawned("valley.village.guard_1") as EnemyActor
	assert_true(guard != null and guard.entity.team == CombatEntity.Team.NEUTRAL and guard.at_peace(),
		"its guards keep the peace")
	var forge := _prop("valley.village.forge") as Forge
	assert_false(forge.is_open(), "the village forge stays cold")
	assert_eq(str(forge.can_upgrade(player).get("reason", "")), "closed", "and refuses the giant")
	s = await _talk_to_elder()
	if s != null:
		assert_eq(s.node_id, "done_cowed", "she only wants it gone")
		assert_eq(s.find_choice("help_cache"), -1, "no help is offered any more")
		await _end_talk()
	_assert_xp_accounted("a second talk")
	await _bridge_to_the_causeway()
	# The armory's rack: the Kingsguard Sword.
	var rack := _prop("valley.ruins.sword_rack") as WeaponRack
	await _go(rack.global_position + Vector3(0, 0, 5), 0.0)
	rack.interact(player)
	await step_ticks(2)
	assert_eq(player.equipment.weapon_id(), "weapon.sword", "the giant takes the Kingsguard Sword")
	await _go(_area("valley.area.causeway"), PI)
	await _kingsfall()
	# The boss checkpoint: death on the return leg after the king and the growth.
	await _go(_marker("valley.marker.practice_gate") + Vector3(4, 0, 0), PI * 0.5)
	await _death_and_reload("the return leg", "valley.shrine.kingsfall")
	assert_eq(WorldState.get_flag("world.ogre_king.defeated"), true, "the Ogre King stays dead")
	assert_eq(player.current_growth_stage(), 3, "the giant comes back at stage 3")
	assert_eq(player.equipment.weapon_id(), "weapon.tree_oak", "with its tree")
	var arena := level.get_node("Kingsfall/BossArena") as BossArena
	assert_true(arena.is_defeated(), "the arena stays open")
	await _go(Vector3(150, 0, 110), PI)
	assert_true(director.spawned(KING) == null, "no king in Kingsfall")
	await _giantforge("weapon.sword")
	assert_true(player.equipment.owns("weapon.sword_reinforced"), "the Kingsguard Blade")
	await _return_leg()
	await _assert_the_end("intimidate")
	assert_false(WorldState.has_flag("reward.village.help"), "no help reward")
	assert_eq(Quests.quest_state("quest.village_cache"), Quests.INACTIVE, "no branch quest started")
	assert_eq(Quests.quest_state("quest.village_ogre"), Quests.INACTIVE, "neither of them")


func test_force_the_smashed_barricade() -> void:
	outcome = "force"
	await _new_game()
	await _forest_to_the_grove()
	await _road_to_thornwick()
	var s := await _talk_to_elder()
	if s == null:
		return
	var leave := -1
	for c: Dictionary in s.choices():
		if str(c.text) == "Not now.":
			leave = int(c.index)
	assert_true(leave >= 0, "the giant may walk away")
	s.choose(leave)
	await _end_talk()
	assert_false(WorldState.has_flag("quest.village.outcome"), "talking sets no outcome")
	# Two blows on a guard turn the village hostile, but never set the outcome.
	var guard := director.spawned("valley.village.guard_1") as EnemyActor
	await _go(guard.global_position + Vector3(-4, 0, 0), -PI * 0.5)
	_strike("valley.village.guard_1", 1.0)
	await step_ticks(3)
	assert_true(FactionState.is_warned("village"), "a first blow warns")
	_strike("valley.village.guard_1", 1.0)
	await step_ticks(3)
	assert_true(FactionState.is_hostile("village"), "a second one within 30 s turns the village hostile")
	assert_false(WorldState.has_flag("quest.village.outcome"), "but sets no outcome")
	assert_eq(Quests.stage_of("quest.main"), "village", "the village still has to be settled")
	await _clear_encounter("encounter.village_guards")
	s = await _talk_to_elder()
	if s != null:
		assert_eq(s.node_id, "hostile", "the elder sends the giant away")
		assert_eq(s.find_choice("help_cache"), -1, "no help is offered")
		await _end_talk()
	# Only the smashed barricade sets force.
	var barricade := _prop("valley.village.barricade") as BreakableProp
	await _go(barricade.global_position + Vector3(-7, 0, 0), -PI * 0.5)
	_strike("valley.village.barricade", 1.0e6)
	await step_ticks(3)
	assert_true(barricade.destroyed, "a stage-2 giant smashes the barricade")
	await _village_settled("force")
	var forge := _prop("valley.village.forge") as Forge
	assert_false(forge.is_open(), "the village forge stays cold")
	await _death_and_reload("force", "valley.shrine.thornwick")
	await _bridge_to_the_causeway()
	await _kingsfall()
	await _giantforge("weapon.club")
	assert_true(player.equipment.owns("weapon.club_reinforced"), "the reinforced club after the boss")
	await _return_leg()
	await _assert_the_end("force")
	assert_false(WorldState.has_flag("reward.village.help"), "no help reward")
	assert_false(WorldState.has_flag("reward.village.intimidate"), "no intimidation reward")
