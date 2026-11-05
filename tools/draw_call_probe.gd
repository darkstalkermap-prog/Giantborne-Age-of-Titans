extends Node3D
## Draw calls of the Valley's static world (P17b; docs/PERFORMANCE.md). Loads the Valley without its
## encounter director and its giant (no actors at all), puts a camera where a stage-1 giant's
## camera would be at each stop of P14's Valley walk (6.5 m behind and 3.4 m above the stop's
## objective marker), turns it through eight directions, and prints per stop the largest view's
## draw calls and the same view with each group hidden (Props, Districts, Shrines, Waystones,
## Dummies, Signs, Kingsfall, the scenery groups), then the largest of all. It needs a renderer:
##
##   xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --resolution 640x360 \
##     --audio-driver Dummy res://tools/draw_call_probe.tscn -- --no-user-settings --q=low
##
## --q=low|medium picks the graphics preset (LevelRoot applies the level record's). Tools only:
## never exported, not part of the game.

const STOPS := ["valley.marker.dummies", "valley.marker.forest_trail", "valley.marker.wolves_a",
	"valley.marker.hunters", "valley.marker.ogre_clearing", "valley.marker.grove_shrine",
	"valley.marker.village_gate", "valley.marker.elder", "valley.marker.field_ogre",
	"valley.marker.quarry_cache", "valley.marker.crown", "valley.marker.bridge",
	"valley.marker.ruins_courtyard", "valley.marker.causeway", "valley.marker.kingsfall_shrine",
	"valley.marker.kingsfall_oak"]
const GROUPS := ["Props", "Districts", "Shrines", "Waystones", "Dummies", "Signs", "Kingsfall"]
const SCENERY_GROUPS := ["scenery", "valley_scenery"]
const DIRECTIONS := 8

var level: Node3D
var cam: Camera3D


func _ready() -> void:
	var quality := "low"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--q="):
			quality = a.substr(4)
	get_node("/root/Settings").set("graphics_override", quality)   # (by path: tools compile alone too)
	level = (load("res://scenes/world/valley.tscn") as PackedScene).instantiate()
	for n in ["EncounterDirector", "Player"]:
		var child := level.get_node_or_null(n)
		if child != null:
			level.remove_child(child)
			child.free()
	add_child(level)
	cam = Camera3D.new()
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	var worst := 0
	for id: String in STOPS:
		var m := level.call("marker", id) as Node3D
		if m == null:
			continue
		var best := -1
		var parts := {}
		for k in DIRECTIONS:
			var yaw := TAU * k / float(DIRECTIONS)
			var at := m.global_position
			cam.global_position = at + Vector3(sin(yaw), 0.0, cos(yaw)) * 6.5 + Vector3.UP * 3.4
			cam.look_at(at + Vector3.UP * 2.0, Vector3.UP)
			var calls := await _calls()
			if calls > best:
				best = calls
				parts = await _without_each_group()
		worst = maxi(worst, best)
		print("DRAW_CALLS %-18s %4d  %s" % [id.trim_prefix("valley.marker."), best, JSON.stringify(parts)])
	print("DRAW_CALLS max %d (%s)" % [worst, quality])
	get_tree().quit()


func _calls() -> int:
	for i in 3:
		await get_tree().process_frame
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


## The current view's draw calls with each group (and the scenery) hidden in turn.
func _without_each_group() -> Dictionary:
	var out := {}
	for group: String in GROUPS:
		var n := level.get_node_or_null(group) as Node3D
		if n == null:
			continue
		n.visible = false
		out[group] = await _calls()
		n.visible = true
	var scenery: Array = []
	for g: String in SCENERY_GROUPS:
		scenery.append_array(get_tree().get_nodes_in_group(g))
	for s in scenery:
		(s as Node3D).visible = false
	out["scenery"] = await _calls()
	for s in scenery:
		(s as Node3D).visible = true
	return out
