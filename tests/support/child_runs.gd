class_name ChildRuns
extends RefCounted
## D3 (the gate tier's time): the child Godot runs a gate suite compares - a run with the skin or the audio and the
## same run without, two seeds of one bot - are independent processes, so they run side by side instead of one after
## the other: the same runs, the same arguments, the same output read the same way, in about half the wall time. Each
## child's output goes to a file of its own under user://child_runs (the shell's redirection: OS.execute would block
## on the first child), its exit code after a marker line; the parent waits for all of them. The children are
## seeded and tick-driven (--fixed-fps), so the machine's load does not change what they print (the determinism
## suites compare exactly that, as they did run one by one on a loaded machine).

const EXIT_MARKER := "__CHILD_RUN_EXIT__ "
const DIR := "user://child_runs"
## A child that has not ended after this long is stopped (its result is then missing: the suite fails).
const TIMEOUT_S := 1500.0


## Runs each of `arg_lists` (the Godot executable's arguments) as its own child process, all at once. Returns one
## {"code", "output"} per list, in order (code -1 when the child was stopped at TIMEOUT_S).
static func run_all(arg_lists: Array) -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var started := Time.get_ticks_msec()
	var jobs: Array = []
	for i in arg_lists.size():
		var path := ProjectSettings.globalize_path("%s/child_%d_%d.log" % [DIR, OS.get_process_id(), i])
		DirAccess.remove_absolute(path)
		var cmd := _quote(OS.get_executable_path())
		for a: String in arg_lists[i]:
			cmd += " " + _quote(a)
		cmd += " > %s 2>&1; echo \"%s$?\" >> %s" % [_quote(path), EXIT_MARKER, _quote(path)]
		var pid := OS.create_process("sh", PackedStringArray(["-c", cmd]))
		jobs.append({"pid": pid, "path": path})
	var running := true
	while running:
		running = false
		for j: Dictionary in jobs:
			if int(j.pid) > 0 and OS.is_process_running(int(j.pid)):
				running = true
		if running:
			if (Time.get_ticks_msec() - started) / 1000.0 > TIMEOUT_S:
				for j: Dictionary in jobs:
					if int(j.pid) > 0 and OS.is_process_running(int(j.pid)):
						OS.kill(int(j.pid))
				break
			OS.delay_msec(100)
	var out: Array = []
	for j: Dictionary in jobs:
		var text := FileAccess.get_file_as_string(str(j.path)) if int(j.pid) > 0 else ""
		var code := -1
		var at := text.rfind(EXIT_MARKER)
		if at >= 0:
			code = int(text.substr(at + EXIT_MARKER.length()).strip_edges())
			text = text.substr(0, at)
		out.append({"code": code, "output": text.trim_suffix("\n")})
	return out


static func _quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


# --------------------------------------------------------------------------- Dgate: a tier's children ahead of time

## Dgate (the slow tier's time): the rendered suites each run one child Godot under Xvfb and wait for it - minutes of the
## tier spent with three of the machine's four CPUs idle. A suite may name its children ahead (a static
## `prefetch_children() -> Array` of [executable, args]); the runner queues them as its tier starts and runs them in the
## background one at a time, in the suites' order, while the suites before them run (pump). The suite then calls
## execute() exactly where it called OS.execute: the same executable, the same arguments, the same output, read the same
## way - the child ran earlier, that is all. A child nobody prefetched runs then and there, as before. While a suite that
## judges wall-clock budgets runs (BudgetRule: a quiet machine's measure) no child runs beside it (quiet).

const PREFETCH_AT_ONCE := 1

static var _queue: Array = []        ## [{"key", "exe", "args"}] not started yet, in order
static var _running: Dictionary = {}  ## key -> {"pid", "path"}
static var _done: Dictionary = {}     ## key -> {"code", "output"}
static var _serial := 0


static func key_of(exe: String, args: PackedStringArray) -> String:
	return exe + "\u0001" + "\u0001".join(args)


## Queues a child to run in the background before its suite asks for it (execute).
static func prefetch(exe: String, args: PackedStringArray) -> void:
	var key := key_of(exe, args)
	if _running.has(key) or _done.has(key):
		return
	for j: Dictionary in _queue:
		if str(j.key) == key:
			return
	_queue.append({"key": key, "exe": exe, "args": args})


## Collects the children that ended; with `may_start`, starts the next queued while fewer than PREFETCH_AT_ONCE run.
static func pump(may_start := true) -> void:
	for key: String in _running.keys():
		var r: Dictionary = _running[key]
		if not OS.is_process_running(int(r.pid)):
			_done[key] = _read(str(r.path))
			_running.erase(key)
	while may_start and _running.size() < PREFETCH_AT_ONCE and not _queue.is_empty():
		var j: Dictionary = _queue.pop_front()
		_start(str(j.key), str(j.exe), j.args as PackedStringArray)


## Waits until no background child runs (before a suite that measures wall-clock time).
static func quiet() -> void:
	while not _running.is_empty():
		OS.delay_msec(50)
		pump(false)


## The tier's end: waits for what runs, forgets what nobody took (a suite that skipped), drops the queue.
static func settle() -> void:
	_queue.clear()
	quiet()
	_done.clear()


## OS.execute(exe, args, output, true) - its result taken from the background run when it was prefetched (waiting for
## it if it has not ended), else run now.
static func execute(exe: String, args: PackedStringArray, output: Array) -> int:
	var key := key_of(exe, args)
	for i in _queue.size():
		if str(_queue[i].key) == key:
			_queue.remove_at(i)
			break
	while _running.has(key):
		OS.delay_msec(50)
		pump(false)
	if _done.has(key):
		var r: Dictionary = _done[key]
		_done.erase(key)
		if int(r.code) >= 0:
			output.append(str(r.output))
			return int(r.code)
	return OS.execute(exe, args, output, true)   # (not prefetched, or its run lost: now, as before)


static func _start(key: String, exe: String, args: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_serial += 1
	var path := ProjectSettings.globalize_path("%s/prefetch_%d_%d.log" % [DIR, OS.get_process_id(), _serial])
	DirAccess.remove_absolute(path)
	var cmd := _quote(exe)
	for a: String in args:
		cmd += " " + _quote(a)
	cmd += " > %s 2>&1; echo \"%s$?\" >> %s" % [_quote(path), EXIT_MARKER, _quote(path)]
	var pid := OS.create_process("sh", PackedStringArray(["-c", cmd]))
	if pid <= 0:
		return   # (not started: execute() runs it then)
	_running[key] = {"pid": pid, "path": path}


static func _read(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var code := -1
	var at := text.rfind(EXIT_MARKER)
	if at >= 0:
		code = int(text.substr(at + EXIT_MARKER.length()).strip_edges())
		text = text.substr(0, at)
	DirAccess.remove_absolute(path)
	return {"code": code, "output": text}
