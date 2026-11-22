extends IntegrationSuite
## A3: TitanTerritory (scripts/world/titan_territory.gd), a titan's ground in the open world, on the quarry test arena
## (its A2 BossArena replaced by a territory about Stoneback's place: he sees within 30 m, hunts to 40 + 10 m):
##   * a giant beyond his sight is unseen (waiting); within it he engages (boss_engaged once), and the POI named is
##     discovered (here none: the arena has no world index);
##   * while engaged he is told where the giant is every second (the hunt), so he turns on it wherever it goes;
##   * the giant beyond his line for disengage_s: boss_disengaged(left), his health and plates whole, and he walks
##     home; seen again, a new attempt;
##   * a region the giant does not stand in keeps him blind (sees()).

const QUARRY := "res://scenes/test/quarry_test.tscn"

var _engaged: Array = []
var _left: Array = []


func before_each() -> void:
	await super()
	_engaged.clear()
	_left.clear()
	Events.boss_engaged.connect(_on_engaged)
	Events.boss_disengaged.connect(_on_left)


func after_each() -> void:
	if Events.boss_engaged.is_connected(_on_engaged):
		Events.boss_engaged.disconnect(_on_engaged)
	if Events.boss_disengaged.is_connected(_on_left):
		Events.boss_disengaged.disconnect(_on_left)
	await super()


func _on_engaged(t: int, id: String) -> void:
	_engaged.append([t, id])


func _on_left(t: int, id: String, reason: String) -> void:
	_left.append([t, id, reason])


func test_he_sights_hunts_lets_go_and_goes_home() -> void:
	var level := (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	var old := level.get_node("BossArena")
	level.remove_child(old)
	old.free()
	var terr := TitanTerritory.new()
	terr.name = "Territory"
	terr.boss_id = "test.quarry.stoneback"
	terr.encounter_id = ""
	terr.engage_area_id = ""
	terr.gate_path = NodePath("")
	terr.pillars_path = NodePath("")
	terr.defeated_flag = "test.territory.defeated"
	terr.territory_m = 30.0
	terr.region_id = ""
	terr.inner_radius_m = 40.0
	terr.disengage_margin_m = 10.0
	terr.disengage_s = 1.0
	terr.position = Vector3(0, 0, -22)
	level.add_child(terr)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var t := level.get_node("Stoneback") as TitanEnemy
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, 6)
	p.global_position = Vector3(0, 0.05, 58)
	await step_ticks(30)
	assert_eq(terr.state_name(), "waiting", "the giant 80 m away is unseen")
	assert_true(terr.sees(Vector3(0, 0, 0)), "sees() within 30 m")
	assert_false(terr.sees(Vector3(0, 0, 58)), "not beyond it")
	terr.region_id = "region.nowhere"
	assert_false(terr.sees(Vector3(0, 0, 0)), "nor in another region")
	terr.region_id = ""
	p.global_position = Vector3(0, 0.05, 6)
	await step_ticks(2)
	assert_eq(terr.state_name(), "engaged", "within 30 m: engaged")
	assert_eq(_engaged.size(), 1, "boss_engaged once")
	assert_eq(terr.sighted, 1, "by sight")
	# the hunt: wherever the giant goes inside his line, he knows
	p.global_position = Vector3(-30, 0.05, 0)
	await step_ticks(70)
	assert_true(t.brain.last_known.distance_to(p.global_position) < 2.0, "he knows where the giant is (%s)" % [
		t.brain.last_known])
	# a blow and a plate cracked: the escape makes him whole
	t.entity.combatant.pools.health = t.entity.combatant.pools.health_max * 0.5
	t.break_plate("shoulder_l")
	await step_ticks(200)
	p.global_position = Vector3(0, 0.05, 60)
	await step_ticks(3)
	assert_eq(terr.state_name(), "engaged", "just past his line: still engaged (disengage_s 1)")
	await step_ticks(70)
	assert_eq(_left.size(), 1, "the escape ends the hunt")
	assert_eq(str(_left[0][2]) if not _left.is_empty() else "", "left", "boss_disengaged left")
	assert_eq(terr.state_name(), "waiting", "his territory waits again")
	assert_eq(t.entity.combatant.pools.health, t.entity.combatant.pools.health_max, "whole again")
	assert_eq(t.plates().broken_count(), 0, "his plates whole again")
	assert_true(t.is_returning(), "he walks home")
	p.global_position = Vector3(0, 0.05, 0)
	await step_ticks(3)
	assert_eq(_engaged.size(), 2, "seen again: a new attempt")
	level.queue_free()
	await step_ticks(2)
