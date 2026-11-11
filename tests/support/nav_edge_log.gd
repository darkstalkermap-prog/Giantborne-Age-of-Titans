class_name NavEdgeLog
extends Logger
## M7 polish (tests): counts the edge errors the navigation server's syncs warn about - "Navigation
## region synchronization had N edge error(s)" (a region's own polygons) and "Navigation map
## synchronization had N edge error(s)" (edges of different regions on one key) - so a test can fail
## on them (the test runner's own logger ignores warnings). Install it with OS.add_logger, read
## edge_errors(), take it out with OS.remove_logger. Callbacks may arrive from other threads.

var _mutex := Mutex.new()
var _errors := 0
var _warnings := 0


func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var text := rationale if rationale != "" else code
	if not text.contains("edge error"):
		return
	var n := 1
	var words := text.split(" ")
	for k in words.size() - 1:
		if words[k] == "had":
			n = int(words[k + 1])
	_mutex.lock()
	_errors += n
	_warnings += 1
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## The edge errors warned about since the last reset().
func edge_errors() -> int:
	_mutex.lock()
	var n := _errors
	_mutex.unlock()
	return n


## How many such warnings arrived (one per region or map sync that had any).
func warnings() -> int:
	_mutex.lock()
	var n := _warnings
	_mutex.unlock()
	return n


func reset() -> void:
	_mutex.lock()
	_errors = 0
	_warnings = 0
	_mutex.unlock()
