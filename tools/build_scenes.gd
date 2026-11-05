extends Node
## Scene generator for the low-poly prototype: runs the scene builders in tools/builders/.
##
##   godot --headless --path . res://tools/build_scenes.tscn                     # every builder
##   godot --headless --path . res://tools/build_scenes.tscn -- --only=wolf,sandbox
##
## (Runs as a scene, not with -s, so autoload names resolve when gameplay scripts compile.)
## Writes Godot-serialized .tscn/.tres files, so they open and edit normally in the editor.
## The generated scenes are the source of truth afterwards: re-running this tool OVERWRITES
## manual edits to those files. Gameplay numbers live in data/*.json, not here.
##
## BUILDERS is pre-declared for every planned builder (plan §2.12), in dependency order: a
## later builder instances scenes that earlier ones saved. A missing file is skipped with a
## note, so a package adds its builder by creating the file, never by editing this list.
## Each builder is a script with `static func build_all(kit: SceneKit) -> void`.

const BUILDERS := [
	"res://tools/builders/player.gd",          # P04: the giant
	"res://tools/builders/soldier.gd",         # P04
	"res://tools/builders/wolf.gd",            # P04
	"res://tools/builders/props.gd",           # P04: practice dummy, wooden fence
	"res://tools/builders/shrine.gd",          # P05
	"res://tools/builders/growth_course.gd",   # P05
	"res://tools/builders/test_levels.gd",     # P06
	"res://tools/builders/world_props.gd",     # P08
	"res://tools/builders/ranged.gd",          # P09
	"res://tools/builders/test_director.gd",   # P10a
	"res://tools/builders/forge.gd",           # P12
	"res://tools/builders/heavy.gd",           # P11a
	"res://tools/builders/npcs.gd",            # P11b
	"res://tools/builders/sandbox.gd",         # P04 (P05, P08 and P11b add to it)
	"res://tools/builders/valley.gd",          # P10b
	"res://tools/builders/stress.gd",          # P14
	"res://tools/builders/main.gd",            # P04
]

const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_BAD_ARGS := 2


func _ready() -> void:
	var picked := select(BUILDERS, parse_only(OS.get_cmdline_user_args()))
	if not picked.ok:
		push_error("build_scenes: %s" % picked.error)
		get_tree().quit(EXIT_BAD_ARGS)
		return
	var kit := SceneKit.new()
	var result := run(kit, picked.paths)
	print("build_scenes: done (%d builders, %d scenes)" % [result.ran, kit.saved.size()])
	get_tree().quit(EXIT_OK if result.ok else EXIT_FAILED)


## Runs the builders at `paths` (in order) with `kit`; missing files are skipped with a note.
## Returns {"ok": bool, "ran": int, "skipped": PackedStringArray}.
static func run(kit: SceneKit, paths: Array) -> Dictionary:
	kit.make_materials()
	var out := {"ok": true, "ran": 0, "skipped": PackedStringArray()}
	for path: String in paths:
		if not ResourceLoader.exists(path):
			print("build_scenes: skipped %s (not present yet)" % path)
			(out.skipped as PackedStringArray).append(path)
			continue
		var script := load(path) as GDScript
		if script == null or not _has_build_all(script):
			push_error("build_scenes: %s has no static build_all(kit)" % path)
			out.ok = false
			continue
		var before := kit.saved.size()
		script.call("build_all", kit)
		out.ran = int(out.ran) + 1
		print("build_scenes: %s -> %d scene(s)" % [builder_name(path), kit.saved.size() - before])
	return out


static func _has_build_all(script: GDScript) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if m.name == "build_all":
			return true
	return false


## The names given after --only= (comma-separated); [] when the option is absent.
static func parse_only(user_args: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for arg in user_args:
		if arg.begins_with("--only="):
			for part in arg.trim_prefix("--only=").split(",", false):
				var builder := part.strip_edges().trim_suffix(".gd")
				if builder != "" and not out.has(builder):
					out.append(builder)
	return out


## A builder's short name: its file name without ".gd" ("res://tools/builders/wolf.gd" -> "wolf").
static func builder_name(path: String) -> String:
	return path.get_file().trim_suffix(".gd")


## The builder paths to run for `only` (empty = all), kept in BUILDERS order. Unknown names are
## an error: {"ok": false, "error": ...}; otherwise {"ok": true, "paths": [...]}.
static func select(all: Array, only: PackedStringArray) -> Dictionary:
	if only.is_empty():
		return {"ok": true, "paths": all.duplicate()}
	var known := {}
	for path: String in all:
		known[builder_name(path)] = path
	var unknown := PackedStringArray()
	for builder in only:
		if not known.has(builder):
			unknown.append(builder)
	if not unknown.is_empty():
		return {"ok": false, "error": "unknown builder(s) %s (known: %s)" % [", ".join(unknown),
			", ".join(PackedStringArray(known.keys()))]}
	var paths: Array = []
	for path: String in all:
		if only.has(builder_name(path)):
			paths.append(path)
	return {"ok": true, "paths": paths}
