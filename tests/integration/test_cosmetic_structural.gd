extends IntegrationSuite
## Selective destruction, decision 23 (plan §3.8): the structural practice gate goes intact ->
## cracked (at or below 50 %, still blocking) -> broken (collision gone, nav link open), with
## object_stage_changed once per stage and the destruction's XP and loot once; its damage is saved
## and restored silently. Cosmetic props (bush, banner) have no CombatEntity and are never saved:
## a Footfall beside a bush makes it react once and leaves WorldState.deltas untouched, a sweep
## through a bush queues no hit, a giant passing makes it wobble and a stage-2+ giant flattens it.
## Also the debris layouts.

const GATE := "res://scenes/world/gate_practice.tscn"
const BUSH := "res://scenes/world/bush.tscn"
const BANNER := "res://scenes/world/banner.tscn"

var stage_events: Array = []
var xp_requests: Array = []


func before_each() -> void:
	await super()
	stage_events.clear()
	xp_requests.clear()
	Events.object_stage_changed.connect(_on_stage)
	Events.xp_award_requested.connect(_on_xp)


func after_each() -> void:
	for sig: Signal in [Events.object_stage_changed, Events.xp_award_requested]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_stage(_tick: int, world_id: String, index: int, stage_id: String) -> void:
	stage_events.append([world_id, index, stage_id])


func _on_xp(amount: int, source: String) -> void:
	xp_requests.append([amount, source])


func _gate(pos: Vector3, world_id: String) -> BreakableProp:
	var g := (load(GATE) as PackedScene).instantiate() as BreakableProp
	g.world_id = world_id
	g.position = pos
	world.add_child(g)
	return g


func _cosmetic(path: String, pos: Vector3) -> CosmeticProp:
	var c := (load(path) as PackedScene).instantiate() as CosmeticProp
	c.position = pos
	world.add_child(c)
	return c


## A player hit dealing `damage` to a prop with `armor` (power x 1.15 x 100 / (100 + armor)).
func _player_hit(target_id: String, at: Vector3, damage: float, armor := 10.0) -> void:
	queue_hit("player", target_id, at, damage / (1.15 * 100.0 / (100.0 + armor)))
	await step_ticks(2)


# --------------------------------------------------------------------------- structural

func test_the_practice_gate_cracks_then_breaks() -> void:
	var p := spawn_player(Vector3(0, 0.05, 8))
	var g := _gate(Vector3(0, 0, 0), "test.gate")
	await step_ticks(2)
	assert_true(g.is_structural(), "the practice gate is structural")
	assert_eq(g.stages.size(), 3, "three authored stages")
	assert_true((g.get_node("Intact") as Node3D).visible, "it starts intact")
	assert_false((g.get_node("Cracked") as Node3D).visible or (g.get_node("Broken") as Node3D).visible, "with the other stages hidden")
	assert_false(g.nav_links_enabled(), "its nav link is closed")
	assert_eq(g.nav_links().size(), 1, "it has one")
	await _player_hit("test.gate", Vector3(0, 1, 3), 100.0)
	assert_near(g.health(), 140.0, 1e-4, "240 - 100")
	assert_eq(g.stage_index, 0, "58 % health: still intact")
	assert_true(stage_events.is_empty(), "no stage event yet")
	assert_eq(int(WorldState.get_delta("test.gate").damage_stage), 0, "every damaging hit is saved: stage 0")
	assert_near(float(WorldState.get_delta("test.gate").health), 140.0, 1e-4, "and its health")
	await _player_hit("test.gate", Vector3(0, 1, 3), 20.0)
	assert_near(g.health_fraction(), 0.5, 1e-6, "exactly 50 %")
	assert_eq(g.stage_id(), "cracked", "at or below 50 %: cracked")
	assert_true((g.get_node("Cracked") as Node3D).visible, "the Cracked visual shows")
	assert_false((g.get_node("Intact") as Node3D).visible, "the Intact one is hidden")
	assert_true(g.has_collision(), "a cracked gate still blocks")
	assert_false(g.nav_links_enabled(), "and its nav link stays closed")
	assert_eq(stage_events, [["test.gate", 1, "cracked"]], "object_stage_changed fires for the crack")
	await _player_hit("test.gate", Vector3(0, 1, 3), 50.0)
	assert_eq(stage_events.size(), 1, "further damage in the same stage fires nothing")
	assert_true(xp_requests.is_empty() and loot.is_empty() and destroyed.is_empty(), "nothing awarded before it breaks")
	await _player_hit("test.gate", Vector3(0, 1, 3), 200.0)
	assert_true(g.destroyed, "at 0 health it breaks")
	assert_eq(g.stage_id(), "broken", "into its last stage")
	assert_eq(stage_events, [["test.gate", 1, "cracked"], ["test.gate", 2, "broken"]], "object_stage_changed once per stage")
	assert_true((g.get_node("Broken") as Node3D).visible and not (g.get_node("Cracked") as Node3D).visible, "the Broken visual")
	assert_false(g.has_collision(), "the broken gate no longer blocks")
	assert_false(is_instance_valid(g.get_node_or_null("BlockLeaves")), "its blocking shape is gone")
	assert_true(is_instance_valid(g.get_node_or_null("PostLeft")), "the stone posts stay")
	assert_true(g.nav_links_enabled(), "its nav link opened")
	assert_eq(destroyed, ["test.gate"] as Array[String], "object_destroyed once")
	assert_eq(xp_requests, [[20, "prop:test.gate"]], "the destruction's 20 XP, requested once")
	assert_eq(loot, ["test.gate:item.wood_scrap"] as Array[String], "its loot once")
	assert_true(bool(WorldState.get_flag("world.ruins.gate_broken", false)), "its on_destroyed_flags")
	assert_true(WorldState.is_destroyed("test.gate"), "a destroyed delta")
	assert_eq(int(WorldState.get_delta("test.gate").damage_stage), 2, "with the last stage")
	var resolved := hits_on("test.gate").size()
	await _player_hit("test.gate", Vector3(0, 1, 3), 50.0)
	assert_eq(hits_on("test.gate").size(), resolved, "the wreck ignores hits (IGNORED: no hit_resolved)")
	assert_eq(stage_events.size(), 2, "no more stage events")
	assert_eq(xp_requests.size(), 1, "no more XP")
	assert_eq(loot.size(), 1, "no more loot")
	p.queue_free()


## A gate broken by somebody else (a synthetic tester) gives no XP; a single huge blow skips the
## cracked stage straight to broken.
func test_xp_only_for_the_player_and_skipped_stages() -> void:
	var g := _gate(Vector3(0, 0, 0), "test.gate_tester")
	await step_ticks(2)
	queue_hit("tester", "test.gate_tester", Vector3(0, 1, 3), 1000.0)
	await step_ticks(2)
	assert_true(g.destroyed, "one blow breaks it")
	assert_eq(stage_events, [["test.gate_tester", 2, "broken"]], "only the stage it entered")
	assert_true(xp_requests.is_empty(), "no XP when the player did not break it")
	assert_eq(loot.size(), 1, "loot still drops once")


## A cracked gate reloads cracked (health, stage, visual, collision, closed link) without events;
## a broken one reloads broken.
func test_damage_stage_and_health_are_restored_silently() -> void:
	spawn_player(Vector3(0, 0.05, 8))
	var g := _gate(Vector3(0, 0, 0), "test.gate_saved")
	await step_ticks(2)
	await _player_hit("test.gate_saved", Vector3(0, 1, 3), 144.0)
	assert_eq(g.stage_id(), "cracked", "cracked at 40 %")
	g.queue_free()
	await step_ticks(2)
	stage_events.clear()
	var again := _gate(Vector3(0, 0, 0), "test.gate_saved")
	await step_ticks(2)
	assert_eq(again.stage_id(), "cracked", "a reloaded gate is cracked")
	assert_near(again.health(), 96.0, 1e-4, "with its saved health")
	assert_true((again.get_node("Cracked") as Node3D).visible and not (again.get_node("Intact") as Node3D).visible,
		"showing the Cracked visual")
	assert_true(again.has_collision(), "still blocking")
	assert_false(again.nav_links_enabled(), "its link closed")
	assert_true(stage_events.is_empty(), "no stage event on load")
	await _player_hit("test.gate_saved", Vector3(0, 1, 3), 200.0)
	assert_true(again.destroyed, "it breaks from there")
	assert_eq(stage_events, [["test.gate_saved", 2, "broken"]], "into broken")
	again.queue_free()
	await step_ticks(2)
	stage_events.clear()
	var third := _gate(Vector3(0, 0, 0), "test.gate_saved")
	await step_ticks(2)
	assert_true(third.destroyed and third.stage_id() == "broken", "a broken gate reloads broken")
	assert_false(third.has_collision(), "without collision")
	assert_true(third.nav_links_enabled(), "with its link open")
	assert_true(stage_events.is_empty() and xp_requests.size() == 1 and loot.size() == 1,
		"and nothing is announced or awarded again")


func test_prop_schema_damage_stages_and_flags() -> void:
	var base := {"schema_version": 1, "id": "prop.test_gate", "type": "prop", "category": "structural",
		"height_m": 6.0, "health": 100, "accepted_attack_categories": ["melee"],
		"damage_stages": [{"id": "intact", "at_or_below_frac": 1.0, "visual": "Intact"},
			{"id": "broken", "at_or_below_frac": 0.0, "visual": "Broken", "removes_collision": true}],
		"on_destroyed_flags": {"world.test.flag": true, "quest.test.outcome": "force", "test.count.n": 2},
		"open_when_flag": "faction.test.open", "required_tags": ["TreeWeapon"], "locked_message": "No.",
		"protected": false, "xp_reward": 5, "requires_permission": "gate_breach", "debris_length_m": 4.0,
		"debris_layout": "pile", "uproot_weapon": "weapon.tree_oak"}
	assert_eq(DataValidator.validate_record(base, "ok.json").errors, PackedStringArray(), "every P08 prop field validates")
	var cases := [
		[{"damage_stages": null}, "'damage_stages' is required"],
		[{"damage_stages": [{"id": "intact", "at_or_below_frac": 1.0, "visual": "Intact"}]}, "at least two stages"],
		[{"damage_stages": [{"id": "a", "at_or_below_frac": 0.8, "visual": "A"}, {"id": "b", "at_or_below_frac": 0.0, "visual": "B", "removes_collision": true}]}, "the first stage must be at 1.0"],
		[{"damage_stages": [{"id": "a", "at_or_below_frac": 1.0, "visual": "A"}, {"id": "b", "at_or_below_frac": 0.2, "visual": "B", "removes_collision": true}]}, "the last stage must be at 0.0"],
		[{"damage_stages": [{"id": "a", "at_or_below_frac": 1.0, "visual": "A"}, {"id": "b", "at_or_below_frac": 0.0, "visual": "B"}]}, "must remove the collision"],
		[{"damage_stages": [{"id": "a", "at_or_below_frac": 1.0, "visual": "A"}, {"id": "c", "at_or_below_frac": 0.3, "visual": "C"}, {"id": "b", "at_or_below_frac": 0.5, "visual": "B"}, {"id": "d", "at_or_below_frac": 0.0, "visual": "D", "removes_collision": true}]}, "sorted by descending fraction"],
		[{"on_destroyed_flags": {"Not A Flag": true}}, "flag id"],
		[{"on_destroyed_flags": {"world.test.flag": [1]}}, "expected true/false, a number or a string"],
		[{"open_when_flag": "nope"}, "flag id"],
		[{"react_radius_m": 1.0}, "only for cosmetic props"],
		[{"debris_layout": "spiral"}, "debris_layout"],
		[{"required_tags": ["Sharp"]}, "required_tags"],
	]
	for c: Array in cases:
		var rec := base.duplicate(true)
		for key: String in c[0]:
			if c[0][key] == null:
				rec.erase(key)
			else:
				rec[key] = c[0][key]
		var errors: PackedStringArray = DataValidator.validate_record(rec, "bad.json").errors
		assert_true("\n".join(errors).contains(c[1]), "%s is refused with '%s' (%s)" % [c[0].keys(), c[1], errors])
	var breakable := base.duplicate(true)
	breakable.category = "breakable"
	assert_true("\n".join(DataValidator.validate_record(breakable, "b.json").errors).contains("only for structural props"),
		"damage stages on a breakable are refused")
	for id: String in ["prop.gate_practice", "prop.gate_fortified"]:
		var stages: Array = GameData.get_record(id).damage_stages
		assert_near(float(stages[0].at_or_below_frac), 1.0, 1e-9, "%s starts intact" % id)
		assert_true(bool(stages[-1].removes_collision) and bool(stages[-1].enables_nav_links), "%s ends open" % id)


# --------------------------------------------------------------------------- cosmetic

## A Footfall beside a bush makes it react once; WorldState.deltas stay empty (never saved); a
## light sweep through a bush queues no hit at all; a banner reacts to a roar-sized pulse.
func test_a_footfall_makes_a_bush_react_and_nothing_is_saved() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var bush := _cosmetic(BUSH, Vector3(2.7, 0, 0))
	var far := _cosmetic(BUSH, Vector3(9.0, 0, 0))
	await step_ticks(30)
	assert_true(bush.is_in_group(CosmeticProp.GROUP), "a cosmetic prop")
	assert_true(bush.get_node_or_null("CombatEntity") == null, "with no CombatEntity")
	assert_eq(bush.react_count, 0, "a giant standing 2.7 m away does not touch it (reach %.2f + 0.85)" % bush.react_radius_m)
	p.controller.request(&"slot", {"slot": 1})
	await step_ticks(30)
	assert_true(started.has("player:ability.heavy_footfall"), "the Footfall ran")
	assert_eq(bush.react_count, 1, "the Footfall (3 m) makes the bush react once")
	assert_eq(far.react_count, 0, "a bush 9 m away does not")
	assert_true(WorldState.deltas.is_empty(), "nothing about it is saved (%s)" % [WorldState.deltas])
	assert_true(hits.is_empty(), "and the pulse hit nothing")
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	var front := _cosmetic(BUSH, Vector3(0, 0, -2.6))
	await step_ticks(14)
	var before := front.react_count
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_true(started.has("player:ability.light_1"), "a light swing through the bush")
	assert_true(hits.is_empty(), "queues no hit: a cosmetic prop is not a combat entity")
	assert_eq(front.react_count, before, "and a weapon arc alone does not rustle it")
	var banner := _cosmetic(BANNER, Vector3(-4.0, 0, 3.0))
	await step_ticks(2)
	Events.area_pulse.emit(Sim.tick, "player", "ability.thunder_roar", Vector3.ZERO, 6.0)
	Events.ability_effect.emit(Sim.tick, "player", "ability.thunder_roar", "roar", Vector3.ZERO, 6.0, 0.0, 360.0)
	assert_eq(banner.react_count, 1, "a roar's pulse and its roar effect count once")
	assert_true(WorldState.deltas.is_empty(), "still nothing saved")


## Sweeping Blow's sector reaches a bush in its arc, not one behind the giant.
func test_a_sector_reaches_only_bushes_in_its_arc() -> void:
	var ahead := _cosmetic(BUSH, Vector3(0.5, 0, -3.0))
	var behind := _cosmetic(BUSH, Vector3(0, 0, 3.0))
	await step_ticks(2)
	Events.ability_effect.emit(Sim.tick, "player", "ability.sweeping_blow", "sector", Vector3.ZERO, 3.5, 0.0, 120.0)
	assert_eq(ahead.react_count, 1, "the bush in the 120 degree sector ahead reacts")
	assert_eq(behind.react_count, 0, "the one behind does not")


## Actors passing within reach: a stage-1 giant makes a bush wobble (once on entering), a stage-2
## giant's step flattens it for 4 s.
func test_passing_giants_wobble_or_flatten_bushes() -> void:
	var p := spawn_player(Vector3(0, 0.05, 6))
	var bush := _cosmetic(BUSH, Vector3(0, 0, 0))
	await step_ticks(30)
	assert_eq(bush.react_count, 0, "nobody near")
	p.global_position = Vector3(0.6, 0.05, 0.4)
	await step_ticks(15)
	assert_eq(bush.react_count, 1, "a giant stepping into it makes it react")
	assert_false(bush.flattened, "a stage-1 giant only makes it wobble")
	await step_ticks(30)
	assert_eq(bush.react_count, 1, "once per pass, not every check")
	p.global_position = Vector3(0, 0.05, 8)
	await step_ticks(15)
	assert_true(p.growth.debug_set_stage(2).ok, "stage 2")
	await step_ticks(15)
	p.global_position = Vector3(0.4, 0.05, 0.3)
	await step_ticks(15)
	assert_eq(bush.react_count, 2, "it reacts again when the giant comes back")
	assert_true(bush.flattened, "a stage-2 giant flattens it")
	assert_true(CosmeticProp.flattens(p), "stage 2 and up flatten")
	assert_true(WorldState.deltas.is_empty(), "never saved")


# --------------------------------------------------------------------------- debris

func test_debris_layouts_and_piece_sizes() -> void:
	var fence_piece := BreakableProp.debris_piece_size(8, 8.0, "line")
	assert_near(fence_piece.z, 1.5, 1e-4, "the 8 m, 8-piece fence keeps the M1 plank length")
	assert_near(fence_piece.x, 0.16, 0.002, "and thickness")
	var line := BreakableProp.debris_pieces("test.line", 10, 10.0, "line")
	assert_eq(line.size(), 10, "one piece per debris_count")
	var xs: Array = []
	for piece: Dictionary in line:
		xs.append((piece.transform as Transform3D).origin.x)
	assert_true(absf(float(xs.min()) + 4.5) < 1e-4 and absf(float(xs.max()) - 4.5) < 1e-4,
		"a line spreads along local X over the length (%s .. %s)" % [xs.min(), xs.max()])
	var pile := BreakableProp.debris_pieces("test.pile", 12, 14.0, "pile")
	for piece: Dictionary in pile:
		var o := (piece.transform as Transform3D).origin
		assert_true(Vector2(o.x, o.z).length() <= 14.0 * 0.25 + 1e-4, "a pile stays within a quarter of the length")
		assert_true((piece.velocity as Vector3).y > 0.0, "and is thrown up")
	assert_eq(BreakableProp.debris_pieces("test.pile", 12, 14.0, "pile"), pile, "deterministic per world id")
	var chunk := BreakableProp.debris_piece_size(12, 14.0, "pile")
	assert_true(chunk.y < chunk.x and chunk.x < chunk.z, "pile pieces are chunks (%s)" % chunk)
	var pool := DebrisPool.new()
	world.add_child(pool)
	var g := _gate(Vector3(0, 0, -10), "test.gate_debris")
	await step_ticks(2)
	queue_hit("tester", "test.gate_debris", Vector3(0, 1, -7), 1000.0)
	await step_ticks(2)
	assert_eq(pool.active_count(), 10, "the gate throws its 10 pieces")
	var sizes := pool.active_sizes()
	assert_true(not sizes.is_empty() and sizes[0].is_equal_approx(BreakableProp.debris_piece_size(10, 10.0, "line")),
		"sized from its data (%s)" % [sizes])
	assert_true(g.destroyed, "broken")
