class_name InputBuffer
extends RefCounted
## Holds at most one queued action request for 0.15 s (9 ticks at 60 Hz). A newer request
## replaces the older one. The request is revalidated when consumed; nothing is spent while
## it waits, and an expired request is simply dropped.

const DEFAULT_WINDOW_TICKS := 9

var window_ticks := DEFAULT_WINDOW_TICKS
var kind: StringName = &""
var params: Dictionary = {}
var queued_tick := -1


func push(p_kind: StringName, p_params: Dictionary, now: int) -> void:
	kind = p_kind
	params = p_params
	queued_tick = now


func has_pending() -> bool:
	return kind != &""


## Valid while (now - queued_tick) <= window_ticks: a request queued at tick T can still be
## consumed at T + 9 (0.15 s) and is gone at T + 10.
func is_live(now: int) -> bool:
	return kind != &"" and now - queued_tick <= window_ticks


func expire(now: int) -> bool:
	if kind != &"" and now - queued_tick > window_ticks:
		clear()
		return true
	return false


func clear() -> void:
	kind = &""
	params = {}
	queued_tick = -1
