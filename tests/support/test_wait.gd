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
