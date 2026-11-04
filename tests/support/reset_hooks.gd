class_name ResetHooks
extends RefCounted
## Per-test resets of global state, pre-declared so no package edits the runner or
## tests/integration_suite.gd (plan §2.13). The runner calls BEFORE_EACH before
## suite.before_each() and AFTER_EACH after suite.after_each().
##
## Entries: ["autoload", "<name>", "<method>"] calls /root/<name>.<method>() when that autoload
## exists; ["script", "<path>", "<static method>"] calls the static method when the script
## exists (ResourceLoader.exists). Missing entries are skipped silently. An optional fourth
## element is a failure message reported when the call returns a positive int (how many
## leftovers it had to clean up), e.g. a screen a test forgot to close.

const BEFORE_EACH := [
	["autoload", "GameSession", "reset_for_tests"],   # P06
	["autoload", "Quests", "reset_for_tests"],        # P13
]
const AFTER_EACH := [
	["script", "res://tests/support/test_fixtures.gd", "restore_all"],                    # P02
	["script", "res://ui/screens/screen_stack.gd", "close_all_static", "screen left open"],  # P03
]


## Runs the entries of `list` in order (awaiting any that are coroutines) and returns the
## failure messages of entries whose leftover count was positive.
static func run(list: Array, tree: SceneTree) -> PackedStringArray:
	var problems := PackedStringArray()
	for entry: Array in list:
		if entry.size() < 3:
			continue
		var target: Object = resolve(entry, tree)
		if target == null:
			continue
		var method := str(entry[2])
		if not has_callable(target, method):
			continue
		var result: Variant = await target.call(method)
		if entry.size() > 3 and typeof(result) == TYPE_INT and int(result) > 0:
			problems.append("%s (%d)" % [str(entry[3]), int(result)])
	return problems


## True when `method` can be called on `target`: a method of a node, or a function declared in
## a script resource (static functions are not reported by Object.has_method on the script).
static func has_callable(target: Object, method: String) -> bool:
	if target is Script:
		var s := target as Script
		while s != null:
			for m: Dictionary in s.get_script_method_list():
				if m.name == method:
					return true
			s = s.get_base_script()
		return false
	return target.has_method(method)


## The object an entry calls: the autoload node, or the loaded script. null when missing.
static func resolve(entry: Array, tree: SceneTree) -> Object:
	match str(entry[0]):
		"autoload":
			if tree == null or tree.root == null:
				return null
			return tree.root.get_node_or_null(NodePath(str(entry[1])))
		"script":
			var path := str(entry[1])
			if not ResourceLoader.exists(path):
				return null
			return load(path)
	return null
