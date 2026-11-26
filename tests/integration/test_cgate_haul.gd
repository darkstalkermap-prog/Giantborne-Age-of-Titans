extends IntegrationSuite
## The milestone C gate (docs/systems/Cgate.md): the giant's carrying in play, on the test floor with the real giant.

const LH := "settlement.last_hearth"


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _player(stage := 6) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var duel: Script = load("res://scripts/debug/titan_duel.gd")
	duel.call("prepare", p, stage)
	await step_ticks(2)
	return p


func _source(at: Vector3, load_id: String, load_name: String) -> HaulSource:
	var s := HaulSource.new()
	s.name = "Source"
	s.world_id = "test.source." + load_id
	s.load_id = load_id
	s.load_name = load_name
	s.position = at
	world.add_child(s)
	return s


## G5: E while he carries a load with a man in his reach set the load aside for the grab - the grab took the man (a
## king-stone in both arms and a soldier in one hand), and the haul's own E was lost. E with a load in his arms sets the
## load down (at a site, or back on its pile); it never grabs.
func test_e_with_a_load_never_grabs_a_man_in_reach() -> void:
	var p := await _player(6)
	_source(Vector3(0, 0, -6), "timber", "great timber")
	await step_ticks(2)
	p.interact.refresh()
	p.interact.use_candidate(p.interact.current_candidate())
	await step_ticks(3)
	assert_true(p.haul.is_carrying(), "he carries a timber")
	var s := spawn_soldier(Vector3(0, 0.05, -4.5), 0.0, "cgate_grabbable", false)
	s.entity.team = CombatEntity.Team.ENEMY
	await step_ticks(5)
	s.entity.stagger(4.0, "test")   # (a man reeling from an arrow, a stamp, a fall)
	await step_ticks(2)
	var c: Dictionary = p.grab.find_candidate("hold")
	assert_true(bool(c.ok), "a man stands in his reach, one he could grab with a free hand (%s)" % str(c.get("reason", "")))
	p.router.inject_edge(&"interact")
	await step_ticks(12)
	assert_false(p.grab.is_holding(), "the man is not grabbed")
	assert_false(p.haul.is_carrying(), "E set the load down")
	assert_eq(float(p.motor.speed_mult_sources().get(&"haul", 1.0)), 1.0, "his pace back")
