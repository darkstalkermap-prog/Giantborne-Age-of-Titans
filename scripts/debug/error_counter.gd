class_name ErrorCounter
extends Logger
## Counts every engine and script error (SCRIPT ERROR, push_error, failed engine conditions)
## and, separately, every warning raised while a tool run (autoplay, scenarios) is going, so
## the run can fail instead of "passing" with errors in the log. Same capture logic as the
## test runner's TestErrorLogger, which is not shipped (tests/* is excluded from exports).
## Callbacks may arrive from other threads, hence the mutex.

const MAX_SAMPLES := 20

var _mutex := Mutex.new()
var _errors := 0
var _warnings := 0
var _error_samples: Array[String] = []
var _warning_samples: Array[String] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	# push_error() reports its C++ location; the script frame that called it is more useful.
	for bt in script_backtraces:
		if bt != null and bt.get_frame_count() > 0:
			file = bt.get_frame_file(0)
			line = bt.get_frame_line(0)
			function = bt.get_frame_function(0)
			break
	var text := "%s  (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function]
	_mutex.lock()
	if error_type == ERROR_TYPE_WARNING:
		_warnings += 1
		if _warning_samples.size() < MAX_SAMPLES:
			_warning_samples.append(text)
	else:
		_errors += 1
		if _error_samples.size() < MAX_SAMPLES:
			_error_samples.append(text)
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func error_count() -> int:
	_mutex.lock()
	var n := _errors
	_mutex.unlock()
	return n


func warning_count() -> int:
	_mutex.lock()
	var n := _warnings
	_mutex.unlock()
	return n


## Everything counted so far, then starts from zero:
## {"errors": int, "warnings": int, "error_samples": [..], "warning_samples": [..]}
## (samples: the first MAX_SAMPLES messages of each kind).
func take() -> Dictionary:
	_mutex.lock()
	var out := {"errors": _errors, "warnings": _warnings,
		"error_samples": _error_samples.duplicate(), "warning_samples": _warning_samples.duplicate()}
	_errors = 0
	_warnings = 0
	_error_samples.clear()
	_warning_samples.clear()
	_mutex.unlock()
	return out
