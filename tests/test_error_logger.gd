class_name TestErrorLogger
extends Logger
## Collects every engine/script error raised while tests run (SCRIPT ERROR, push_error, failed
## engine conditions), so a test that crashes before its assertions can never pass silently.
## Warnings are ignored. Callbacks may arrive from other threads, hence the mutex.

var _mutex := Mutex.new()
var _errors: Array[String] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := "%s  (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function]
	_mutex.lock()
	_errors.append(text)
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func take() -> Array[String]:
	_mutex.lock()
	var out := _errors.duplicate()
	_errors.clear()
	_mutex.unlock()
	return out
