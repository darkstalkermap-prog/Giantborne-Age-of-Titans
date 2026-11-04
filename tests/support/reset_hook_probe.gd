class_name ResetHookProbe
extends RefCounted
## Static target for tests/integration/test_reset_hooks.gd ("script" ResetHooks entries).

static var calls: Array[String] = []


static func first() -> void:
	calls.append("script.first")


static func leftovers() -> int:
	calls.append("script.leftovers")
	return 2


static func waits() -> void:
	calls.append("script.waits.begin")
	await (Engine.get_main_loop() as SceneTree).process_frame
	calls.append("script.waits.end")
