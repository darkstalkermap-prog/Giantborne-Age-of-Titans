class_name TestWait
extends RefCounted
## Waiting helpers for integration tests (plan §2.13).


## Steps real ticks until cond() is true, at most max_ticks. Returns cond()'s final value.
## Usage: var ok: bool = await TestWait.until(self, func() -> bool: return x, 60)
static func until(suite: TestSuite, cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if cond.call():
			return true
		await suite.step_ticks(1)
	return cond.call()


## B5 (G11: the titans' duels depended on the suites run before them): every titan duel starts here, before its level
## is made - on a whole second of Sim's clock, with Sim's random streams reseeded. A duel used to wait for the whole
## second only after its level was loaded, so the ticks between the load and that second (0 to 59, set by however many
## ticks the earlier suites had run) were ticks in which the titan's AI already hunted the giant at its spawn - a
## different fight from the first tick on. The actors perceive and decide on ticks of their own phase of Sim's clock
## (EnemyActor._phase_offset), and the crits draw from Sim's rng, so both are fixed here too.
static func duel_start(suite: TestSuite) -> void:
	await until(suite, func() -> bool: return Sim.tick % Sim.TICK_RATE == 0, Sim.TICK_RATE + 1)
	Sim.reseed(Sim.DEFAULT_SEED)


## B5 (G11): a titan duel's own physics space - a SubViewport with its own World3D under `parent` (nothing drawn into
## it); the duel's level goes in it and is freed with it (free the host, not the level). Bodies of earlier fights freed
## from a shared space leave its broadphase in another order: contacts are met in another order and the giant's slide
## along a trunk came out 1e-7 m apart, which a long fight grows into another fight (the Rootwarden's grove duel at
## stage 6: won at 322.1 s alone, at 291.1 s after the stage-5 duel in the same process).
## The space gets IntegrationSuite's floor first (the 120 m box every suite's world starts with), as a process's first
## duel had it: that duel's numbers are what every duel's now are.
static func duel_host(parent: Node) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "DuelHost"
	vp.own_world_3d = true
	vp.size = Vector2i(64, 64)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(vp)
	var b := StaticBody3D.new()
	b.collision_layer = HitQueryAdapter.LAYER_WORLD
	b.collision_mask = 0
	b.position = Vector3(0, -0.5, 0)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120, 1, 120)
	cs.shape = shape
	b.add_child(cs)
	vp.add_child(b)
	return vp
