class_name BudgetRule
extends RefCounted
## M9 gate (final; the final round's README item 4, the early audit's R2): the load rule every wall-clock CPU budget
## test shares (P30's and P39's budgets, measured headless on a machine the team's lanes share). Within its budget a
## measurement passes; over it, it fails on a quiet machine and only warns on a loaded one - the 1-minute load average
## at its start above the CPU count. Lane review gave test_formation_perf this rule; test_unreachable_chase (its 8 ms
## p95 failed the integration's full check at a load of about 9 on 4 CPUs) and the M7 gate's world tick-phase budget
## take it from here too.
## A warning is printed with the suite's other lines ("    BUDGET WARNING <suite>: ...") and noted here: the runner
## prints every one again at column 0 with a "WARNINGS: n" line before its RESULT, and tools/check.sh shows those
## lines in its summary, next to CHECK PASSED - so an over-budget measurement on a loaded machine is seen, not hidden
## in tests.log.

## The warnings of this run (one line each; the runner prints them at the end).
static var warnings: PackedStringArray = PackedStringArray()


## The machine's 1-minute load average (/proc/loadavg) now; -1 where the system has none to read (it is then judged
## as a quiet machine).
static func load_average() -> float:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	if f == null:
		return -1.0
	var first := f.get_line().get_slice(" ", 0)
	return float(first) if first.is_valid_float() else -1.0


## How a wall-clock measurement is judged - "pass" within its budget; over it, "warn" when the load average at the
## measurement's start (`load_start`) was above the machine's `cpus`, else "fail". Pure.
static func verdict(value: float, budget: float, load_start: float, cpus: int) -> String:
	if value <= budget:
		return "pass"
	return "warn" if load_start > float(cpus) else "fail"


## Asserts `value <= budget` in `suite` (its message `line`) - or, over budget on a loaded machine (verdict "warn"),
## prints and notes the measurement as a BUDGET WARNING instead of failing.
static func judge(suite: TestSuite, value: float, budget: float, load_start: float, line: String) -> void:
	var cpus := OS.get_processor_count()
	var full := "%s (load average %.2f at the start, %d CPUs)" % [line, load_start, cpus]
	if verdict(value, budget, load_start, cpus) == "warn":
		var w := "BUDGET WARNING %s: over budget on a loaded machine, reported and not failed - %s" % [suite.name, full]
		print("    " + w)
		warnings.append(w)
		return
	suite.assert_true(value <= budget, full)
