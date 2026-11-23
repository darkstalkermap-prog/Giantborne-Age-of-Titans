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
