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
