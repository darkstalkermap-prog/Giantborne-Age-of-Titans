extends IntegrationSuite
## M7 gate review fixes (plan M6-M9 §0.2's M7 row; the slow half on the real world is
## tests/slow/test_m7_gate_world.gd):
##   * formations and the leash: an encounter's formations must reach no farther than its leash
##     (FormationRules.reach_m: every slot, wherever the pivot may advance and turn; an advancing
##     formation must name advance_m) - the toll fort's pikes reached 68.3 m with a 45 m leash and
##     the director leashed the front rank the moment it advanced; the director leaves a member of
##     an intact formation to its formation and leashes the members of a broken one like any other;
##     and an advancing formation stops inside its brace distance and braces, never in the half
##     metre outside it (where it used to stand "formed" before a still giant);
##   * fast travel and the respawn blockers: Brannock's waystone, while the town is hostile and its
##     guards stand near it, is refused to fast travel with the guards' reason - from the world and
##     from the Valley (the blockers judge the destination's level) - and a load whose respawn a
##     blocker moves says why and where the giant wakes (HUD and last_load_message), never silently.
##     (test_fast_travel has the map's half on its stub levels.)
##   * the brace strikes where its telegraph was drawn: a 4-file pike rank braces at a stage-4 giant
##     5 m ahead and draws its band; the giant side-steps clear of the drawn band while the rank
##     turns after it during the 0.8 s windup; the band strikes along the drawn band (the brace's
##     tracking_fraction is 0) and the giant is not struck (it was: the band turned with the rank).

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const DIRECTOR_LEVEL := "res://scenes/test/director_test.tscn"
const LEASH_ENC := "encounter.m7gate_leash_wall"
const LEASH_CENTER := Vector3(-30, 0, 30)
const LEASH_M := 15.0
const WORLD := "level.world"
const BRANNOCK_CP := "world.cp.brannock"
const KINGS_ROAD_CP := "world.cp.kings_road"


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	await super()


# --------------------------------------------------------------------------- formations and the leash

## An encounter record with one formation of `files` files around (x, z), facing `yaw_deg`.
static func _formation_enc(center: Vector3, leash: float, form: Dictionary, files: int, at: Vector3,
		banner := false) -> Dictionary:
	var spawns: Array = []
	var fs := float(form.get("file_spacing_m", 1.5))
	for i in files:
		var x := (float(i) - float(files - 1) * 0.5) * fs
		spawns.append({"entity_id": "test.m7gate.m%d" % i, "definition": "enemy.pikeman",
			"position_m": [at.x + x, at.y, at.z], "yaw_deg": float(form.get("yaw_deg", 0.0)), "patrol": "",
			"faction": "", "commander": false, "ai_enabled": true, "persist_death": false, "loot_table": "",
			"formation": str(form.id), "slot": i})
	if banner:
		spawns.append({"entity_id": "test.m7gate.banner", "definition": "enemy.bannerman",
			"position_m": [at.x, at.y, at.z + 2.0], "yaw_deg": 0.0, "patrol": "", "faction": "", "commander": false,
			"ai_enabled": true, "persist_death": false, "loot_table": "", "formation": str(form.id), "slot": -1})
	return {"id": "encounter.m7gate_t", "type": "encounter", "level": "level.t",
		"center_m": [center.x, center.y, center.z], "leash_radius_m": leash, "formations": [form], "spawns": spawns}


func test_a_formation_must_reach_no_farther_than_its_encounters_leash() -> void:
	# a rank of three, 1.5 m apart, 20 m north of the centre (yaw 0: facing -Z)
	var form := {"id": "pikes", "kind": "pike", "ranks": 1, "files": 3, "file_spacing_m": 1.5, "yaw_deg": 0,
		"facing": "fixed", "advance_mps": 1.4, "advance_m": 10}
	var enc := _formation_enc(Vector3.ZERO, 40.0, form, 3, Vector3(0, 0, -20))
	# fixed facing: its outer files sqrt(20^2 + 1.5^2) out, plus the 10 m advance
	assert_near(FormationRules.reach_m(enc, form), sqrt(400.0 + 2.25) + 10.0, 1e-3, "a fixed rank's reach")
	assert_eq(FormationRules.record_errors(enc, "t"), PackedStringArray(), "inside a 40 m leash: no error")
	form["facing"] = "threat"
	assert_near(FormationRules.reach_m(enc, form), 20.0 + 1.5 + 10.0, 1e-3, "a turning rank swings its outer files all round")
	enc.leash_radius_m = 30.0
	var errors := FormationRules.record_errors(enc, "t")
	assert_eq(errors.size(), 1, "beyond a 30 m leash: one error (%s)" % [errors])
	assert_true(errors.size() == 1 and errors[0].contains("pikes") and errors[0].contains("31.5"),
		"it names the formation and its reach")
	enc.erase("leash_radius_m")
	assert_eq(FormationRules.record_errors(enc, "t"), PackedStringArray(), "an encounter without a leash has no such rule")
	# an advancing formation without advance_m could walk anywhere
	enc.leash_radius_m = 70.0
	form.erase("advance_m")
	errors = FormationRules.record_errors(enc, "t")
	assert_true(errors.size() == 1 and errors[0].contains("advance_m"), "advancing without advance_m is an error (%s)" % [errors])
	form["advance_mps"] = 0.0
	assert_eq(FormationRules.record_errors(enc, "t"), PackedStringArray(), "a formation that stands needs none")
	# the banner stands a rank behind: it is part of the reach
	var banner_form := {"id": "pikes", "kind": "pike", "ranks": 1, "files": 1, "rank_spacing_m": 2.0, "yaw_deg": 0,
		"facing": "threat", "banner": "test.m7gate.banner"}
	var with_banner := _formation_enc(Vector3.ZERO, 70.0, banner_form, 1, Vector3(0, 0, -20), true)
	assert_near(FormationRules.reach_m(with_banner, banner_form), 22.0, 1e-3, "the banner's 2 m behind the rank count")


func test_the_shipped_formation_fights_reach_no_farther_than_their_leashes() -> void:
	for id: String in ["encounter.crownmarch_toll_fort", "encounter.crownmarch_raiders"]:
		var enc := GameData.get_record(id)
		assert_false(enc.is_empty(), "%s ships" % id)
		var leash := float(enc.get("leash_radius_m", 0.0))
		assert_true(leash > 0.0 and leash <= 70.0, "%s keeps the plan's leash of at most 70 m (%.0f)" % [id, leash])
		for f: Dictionary in enc.formations:
			var reach := FormationRules.reach_m(enc, f)
			print("    %s: %s reaches %.1f m of its %.0f m leash" % [id, f.id, reach, leash])
			assert_true(reach > 30.0 and reach <= leash, "%s's %s reaches %.1f m, inside its leash" % [id, f.id, reach])
		assert_eq(FormationRules.record_errors(enc, id), PackedStringArray(), "%s's formations pass their checks" % id)


## The leash wall: three pikemen in a fixed rank at LEASH_CENTER on the director test level, with a
## LEASH_M leash (no brace, no advance: only the leash is tested).
func _leash_wall() -> Dictionary:
	var form := {"id": "wall", "kind": "pike", "display_name": "Leash Wall", "ranks": 1, "files": 3,
		"rank_spacing_m": 1.4, "file_spacing_m": 1.5, "facing": "fixed", "yaw_deg": 0, "morale_start": 90}
	var enc := _formation_enc(LEASH_CENTER, LEASH_M, form, 3, LEASH_CENTER)
	enc.id = LEASH_ENC
	enc.level = "level.director_test"
	enc.merge({"type": "encounter", "district": "west", "display_name": "M7 gate leash wall", "activate_radius_m": 25,
		"deactivate_radius_m": 200, "alert_group": false, "requires_flags": [], "forbids_flags": [],
		"counts_toward_budget": true}, true)
	return enc


func test_the_director_leaves_an_intact_formations_members_to_it_and_leashes_a_broken_ones() -> void:
	TestFixtures.record_override(LEASH_ENC, _leash_wall())
	var level := (load(DIRECTOR_LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	var director := level.director()
	director.member_spawned.connect(func(_e: String, _id: String, node: Node3D) -> void: node.set("ai_enabled", false))
	level.player().router.use_injection = true
	var leashed: Array[String] = []
	var on_leash := func(_t: int, _enc: String, id: String) -> void: leashed.append(id)
	Events.encounter_leashed.connect(on_leash)
	await step_ticks(1)
	director.force_activate(LEASH_ENC)
	await step_ticks(Formation.UPDATE_TICKS + 1)
	var f := director.formation(Formation.formation_id(LEASH_ENC, "wall"))
	assert_true(f != null and f.is_intact() and f.members.size() == 3, "the wall formed")
	if f == null or f.members.size() < 3:
		Events.encounter_leashed.disconnect(on_leash)
		return
	var m := director.spawned("test.m7gate.m0") as EnemyActor
	m.global_position = LEASH_CENTER + Vector3(0, 0.05, LEASH_M + 10.0)   # pushed out of the leash
	director.update_now()
	assert_false(m.is_returning(), "a member of an intact formation is not leashed: its formation holds it")
	assert_eq(m.leash_count, 0, "no leash began")
	assert_eq(leashed, [] as Array[String], "no encounter_leashed")
	for id: String in ["test.m7gate.m1", "test.m7gate.m2"]:
		queue_hit("player", id, director.spawned(id).global_position + Vector3(0, 0, 2), 100000.0)
	await step_ticks(Formation.UPDATE_TICKS + 1)
	assert_eq(f.state, "broken", "two of three fell: the wall is broken")
	director.update_now()
	assert_true(m.is_returning(), "a member of a broken formation is leashed like any other")
	assert_eq(leashed, ["test.m7gate.m0"] as Array[String], "encounter_leashed for it")
	Events.encounter_leashed.disconnect(on_leash)


# --------------------------------------------------------------------------- the advance ends inside the brace

## A stage-4 giant at `pos` (its profile set directly).
func _stage_4_giant(pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, PI)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	return p


## A rank of three pikemen facing +Z at the origin that advances (1.4 m/s, up to 30 m) and braces
## at 6 m, AI off but aware of the giant.
func _advancing_rank() -> Formation:
	var f := Formation.new()
	f.id = "test.m7gate.advance"
	f.kind = "pike"
	f.ranks = 1
	f.files = 3
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.brace_m = 6.0
	f.brace_action = "ability.formation_brace_pike"
	f.advance_mps = 1.4
	f.advance_m = 30.0
	f.place(Vector3.ZERO, PI)
	Formation.register(f)
	for i in 3:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i) + Vector3(0, 0.05, 0), "test.m7gate.adv_%d" % i,
			false, PI), i)
	return f


func _aware(f: Formation) -> void:
	for e: EnemyActor in f.members:
		e.brain.aware = true


func test_an_advancing_formation_stops_inside_its_brace_distance_and_braces() -> void:
	TestFixtures.record_override("ability.formation_brace_pike", {"windup_s": 0.1, "recovery_s": 0.05})
	var p := _stage_4_giant(Vector3(0, 0.05, 6.3))   # 0.3 m outside the brace distance, straight ahead
	var f := _advancing_rank()
	await step_ticks(1)
	_aware(f)
	f.update(Sim.tick, p)
	assert_eq(f.state, "advancing", "a still giant 0.3 m beyond brace_m is advanced on (it stood 'formed')")
	# from 9 m: it walks in, stops inside the brace distance and braces
	p.global_position = Vector3(0, 0.05, 9.0)
	var braced_at := -1
	for i in 60:
		_aware(f)
		f.update(Sim.tick, p)
		if f.brace_count > 0:
			braced_at = i
			break
		await step_ticks(Formation.UPDATE_TICKS)
	assert_true(braced_at >= 0, "the rank braced (state %s, %.2f m from the giant)" % [f.state, f.front_gap(p.global_position)])
	assert_true(f.front_gap(p.global_position) <= f.brace_m, "inside its brace distance (%.2f m)" % f.front_gap(p.global_position))
	assert_true(f.front_gap(p.global_position) > f.brace_m - Formation.ADVANCE_SLACK_M - 0.3,
		"and no deeper than the slack (%.2f m)" % f.front_gap(p.global_position))


# --------------------------------------------------------------------------- fast travel and the respawn blockers

func test_a_hostile_brannocks_waystone_is_refused_to_fast_travel_and_a_moved_respawn_says_why() -> void:
	FactionState.reset_for_tests()
	GameSession.start_world_for_tests(KINGS_ROAD_CP)
	GameSession.level_id = WORLD
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	assert_eq(GameSession.respawn_id, KINGS_ROAD_CP, "the giant starts at the King's Road waystone")
	var blocker := func(id: String) -> String: return FactionState.respawn_refusal(id)
	GameSession.register_respawn_blocker(blocker)
	for id: String in [BRANNOCK_CP, KINGS_ROAD_CP]:
		WorldState.set_flag(GameSession.VISITED_PREFIX + id, true)
	assert_eq(GameSession.travel_refusal(WORLD, BRANNOCK_CP, "fast_travel"), "", "at peace Brannock's stone is open")
	WorldState.set_flag(FactionState.flag_id("brannock", "hostile"), true)   # the town sworn by force
	var held := "Brannock's guards hold the ground there."
	assert_eq(GameSession.respawn_blocker(BRANNOCK_CP), held, "hostile: its guards refuse a respawn there")
	assert_eq(GameSession.travel_refusal(WORLD, BRANNOCK_CP, "fast_travel"), held,
		"and fast travel there is refused with their reason (it was offered, and the reload woke the giant at the King's Road)")
	assert_eq(GameSession.travel_to(WORLD, BRANNOCK_CP, "fast_travel"), {"ok": false, "message": held}, "travel_to refuses it")
	assert_eq(GameSession.travel_refusal(WORLD, KINGS_ROAD_CP, "fast_travel"), "", "the King's Road stays open")
	# from the Valley the guards are judged in the world, the destination's level
	GameSession.level_id = "level.valley"
	assert_eq(GameSession.respawn_blocker_level(), "level.valley", "standing in the Valley")
	assert_eq(GameSession.travel_refusal(WORLD, BRANNOCK_CP, "fast_travel"), held, "refused from the Valley too")
	GameSession.level_id = WORLD
	# a load whose respawn the guards refuse wakes the giant elsewhere and says so
	var lines: Array[String] = []
	var on_message := func(text: String, _kind: String) -> void: lines.append(text)
	Events.hud_message.connect(on_message)
	assert_true(bool(GameSession.travel_to(WORLD, BRANNOCK_CP, "debug").ok), "a debug travel (no fast-travel rule) to the stone")
	GameSession.last_load_message = ""
	GameSession.on_level_ready(world, p)
	Events.hud_message.disconnect(on_message)
	assert_eq(GameSession.respawn_id, KINGS_ROAD_CP, "the load wakes the giant at the nearest visited open stone")
	var where := GameSession.checkpoint_display_name(KINGS_ROAD_CP, WORLD)
	assert_true(where != "", "which has a name (%s)" % where)
	var expected := "%s You wake at the %s." % [held, where]
	assert_true(lines.has(expected), "the HUD says why and where (%s)" % [lines])
	assert_eq(GameSession.last_load_message, expected, "and so does last_load_message")
	GameSession.unregister_respawn_blocker(blocker)


# --------------------------------------------------------------------------- the brace keeps its telegraphed band

func test_the_brace_strikes_where_its_telegraph_was_drawn_and_misses_a_giant_that_stepped_clear() -> void:
	var p := _stage_4_giant(Vector3(0, 0.05, 5.0))   # 5 m before the rank's centre
	var f := Formation.new()
	f.id = "test.m7gate.band"
	f.kind = "pike"
	f.ranks = 1
	f.files = 4
	f.file_spacing_m = 1.4
	f.brace_m = 6.0
	f.brace_action = "ability.formation_brace_pike"
	f.turn_deg_s = 40.0
	f.place(Vector3.ZERO, PI)   # facing +Z
	Formation.register(f)
	for i in 4:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i) + Vector3(0, 0.05, 0), "test.m7gate.band_%d" % i,
			false, PI), i)
	var telegraphs: Array = []
	var bands: Array = []
	var on_telegraph := func(_t: int, actor: String, action: String, _target: String, _shape: String, origin: Vector3,
			yaw: float, half_width: float, depth: float, _duration: float) -> void:
		if action == "ability.formation_brace_pike":
			telegraphs.append([actor, origin, yaw, half_width, depth])
	var on_effect := func(_t: int, actor: String, action: String, kind: String, center: Vector3, half_width: float,
			yaw: float, depth: float) -> void:
		if action == "ability.formation_brace_pike" and kind == "band":
			bands.append([actor, center, yaw, half_width, depth])
	Events.telegraph_started.connect(on_telegraph)
	Events.ability_effect.connect(on_effect)
	await step_ticks(1)
	var pid := p.entity.entity_id
	var hits_before := hits_on(pid).size()
	# braced: the windup begins and the band is drawn
	for i in 30:
		_aware(f)
		f.update(Sim.tick, p)
		if not telegraphs.is_empty():
			break
		await step_ticks(1)
	assert_eq(telegraphs.size(), 1, "the rank braced and drew its band")
	if telegraphs.is_empty():
		Events.telegraph_started.disconnect(on_telegraph)
		Events.ability_effect.disconnect(on_effect)
		return
	var drawn: Array = telegraphs[0]
	# the giant side-steps clear of the drawn band (its capsule 1 m beyond the band's side) while the
	# rank keeps turning after it (40 degrees a second) through the windup
	p.global_position = Vector3(6.0, 0.05, 4.0)
	var radius := float(p.profile.get("capsule_radius_m", 2.2))
	assert_near(6.0 - radius - float(drawn[3]), 1.0, 0.05, "the giant stands 1 m clear of the drawn band's side")
	for i in 70:
		_aware(f)
		if i % Formation.UPDATE_TICKS == 0:
			f.update(Sim.tick, p)
		await step_ticks(1)
		if not bands.is_empty():
			break
	await step_ticks(2)
	Events.telegraph_started.disconnect(on_telegraph)
	Events.ability_effect.disconnect(on_effect)
	assert_true(absf(rad_to_deg(wrapf(f.facing_yaw - float(drawn[2]), -PI, PI))) > 10.0,
		"the rank turned after the giant during the windup (%.1f -> %.1f degrees)" % [rad_to_deg(float(drawn[2])), rad_to_deg(f.facing_yaw)])
	assert_eq(bands.size(), 1, "the band struck once")
	if bands.size() == 1:
		var struck: Array = bands[0]
		assert_near(rad_to_deg(wrapf(float(struck[2]) - float(drawn[2]), -PI, PI)), 0.0, 1.0,
			"along the drawn band's yaw (drawn %.1f, struck %.1f)" % [rad_to_deg(float(drawn[2])), rad_to_deg(float(struck[2]))])
		var drawn_center: Vector3 = (drawn[1] as Vector3) + Formation.forward_of(float(drawn[2])) * (float(drawn[4]) * 0.5)
		assert_true(Vector2((struck[1] as Vector3).x - drawn_center.x, (struck[1] as Vector3).z - drawn_center.z).length() < 0.01,
			"centred where it was drawn (%s, drawn %s)" % [struck[1], drawn_center])
	assert_eq(hits_on(pid).size() - hits_before, 0, "a giant standing clear of the drawn band is not struck")
