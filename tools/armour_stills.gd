extends Node
## B1: stills of the functional armour on the giant as the game draws it (GiantPreview: the creator's model, the
## world's light or the studio's), one PNG a shot at 1280 x 720 (the evidence for docs/systems/B1.md and the looks'
## own check). Each shot is the default giant (or a preset / a build) wearing a set of armour pieces as the Equipment
## tab dresses him (Armour.dress over his own look), at a stage's Game view or a creator framing, turned and zoomed,
## in the still pose or a clip's frame (idle, walk, roar, stomp).
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/armour_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints ARMOUR_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const SIZE := Vector2i(1280, 720)
const WATCHDOG_S := 900.0
const PREFIX := "ARMOUR_STILLS "
const FRAMES := 4

var out_dir := ""
var only: PackedStringArray = []
var _preview: GiantPreview
var _written := PackedStringArray()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "timed out", "shots": Array(_written)}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--shots="):
			only = arg.substr(8).split(",", false)
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://armour_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_preview = GiantPreview.new()
	_preview.still = true
	_preview.stretch = false
	_preview.world_light = true
	add_child(_preview)
	await get_tree().process_frame
	_run.call_deferred()


## The shots: {name, pieces: [armour ids], hidden: [slots], record (a look; the default's when absent), stage,
## framing, turn, zoom, clip, clip_s, studio}.
static func shots() -> Array:
	var out: Array = []
	var sets := {"quarry": Armour.set_pieces("armour_set.quarry"), "iron": Armour.set_pieces("armour_set.iron"),
		"hide": Armour.set_pieces("armour_set.hide"), "kingsfall": Armour.set_pieces("armour_set.kingsfall")}
	for key: String in sets:
		# the evidence's turnarounds: a stage-5 giant (the model at its scale, framed whole) in the studio's neutral light
		out.append({"name": "set_%s_front" % key, "pieces": sets[key], "framing": "full", "turn": -20.0, "stage": 5,
			"studio": true})
		out.append({"name": "set_%s_back" % key, "pieces": sets[key], "framing": "back", "stage": 5, "studio": true})
		out.append({"name": "set_%s_upper" % key, "pieces": sets[key], "framing": "upper", "turn": -10.0})
		out.append({"name": "set_%s_stomp" % key, "pieces": sets[key], "framing": "full", "turn": 30.0, "clip": "stomp_r",
			"clip_s": 0.45})
	out.append({"name": "quarry_heavy", "pieces": sets.quarry, "framing": "full", "turn": -20.0,
		"build": Vector2(1.0, 1.0), "stage": 5, "studio": true})
	out.append({"name": "quarry_slim", "pieces": sets.quarry, "framing": "full", "turn": -20.0,
		"build": Vector2(-1.0, -1.0), "stage": 5, "studio": true})
	out.append({"name": "iron_heavy", "pieces": sets.iron, "framing": "full", "turn": -20.0, "build": Vector2(1.0, 1.0)})
	out.append({"name": "hide_slim", "pieces": sets.hide, "framing": "full", "turn": -20.0, "build": Vector2(-1.0, -1.0)})
	out.append({"name": "quarry_game_stage5", "pieces": sets.quarry, "framing": "game", "stage": 5})
	out.append({"name": "quarry_walk", "pieces": sets.quarry, "framing": "full", "turn": 60.0, "clip": "walk",
		"clip_s": 0.3})
	out.append({"name": "quarry_roar", "pieces": sets.quarry, "framing": "upper", "turn": 25.0, "clip": "roar",
		"clip_s": 0.9})
	out.append({"name": "none_front", "pieces": [], "framing": "full", "turn": -20.0})
	out.append({"name": "quarry_arms_rest", "pieces": sets.quarry, "framing": "arms", "clip": "rest"})
	out.append({"name": "quarry_arms_t90", "pieces": sets.quarry, "framing": "arms", "turn": 80.0})
	out.append({"name": "quarry_arms_idle", "pieces": sets.quarry, "framing": "arms", "clip": "idle", "clip_s": 0.5})
	for key: String in sets:
		out.append({"name": "%s_shoulders" % key, "pieces": sets[key], "framing": "shoulders"})
		out.append({"name": "%s_arms" % key, "pieces": sets[key], "framing": "arms"})
		out.append({"name": "%s_shins" % key, "pieces": sets[key], "framing": "shins"})
		out.append({"name": "%s_head" % key, "pieces": sets[key], "framing": "head"})
		out.append({"name": "%s_waist" % key, "pieces": sets[key], "framing": "waist"})
		out.append({"name": "%s_chest" % key, "pieces": sets[key], "framing": "chest"})
	out.append({"name": "tassets_kingsfall", "pieces": ["armour.kingsfall_tassets"], "framing": "waist", "turn": 200.0})
	out.append({"name": "tassets_bare", "pieces": ["armour.kingsfall_tassets", "armour.kingsfall_cuirass"], "framing": "full",
		"bare": true})
	out.append({"name": "tassets_bare_w0", "pieces": ["armour.kingsfall_tassets"], "framing": "waist", "bare": true})
	out.append({"name": "tassets_bare_w180", "pieces": ["armour.kingsfall_tassets"], "framing": "waist", "bare": true,
		"turn": 180.0})
	out.append({"name": "tassets_iron", "pieces": ["armour.iron_war_belt"], "framing": "waist", "turn": 30.0})
	out.append({"name": "quarry_hidden_shoulders", "pieces": sets.quarry, "hidden": ["shoulders"], "framing": "upper",
		"turn": -10.0})
	return out


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_preview.custom_minimum_size = Vector2(SIZE)
	_preview.size = Vector2(SIZE)
	_preview.viewport.size = SIZE
	for shot: Dictionary in shots():
		if not only.is_empty() and not str(shot.name) in only:
			continue
		await _render(shot)
	print(PREFIX + JSON.stringify({"shots": Array(_written), "ms": Time.get_ticks_msec() - t0}))
	get_tree().quit(0)


func _render(shot: Dictionary) -> void:
	var record: Dictionary = shot.get("record", Appearance.default_record())
	if bool(shot.get("bare", false)):
		record = record.duplicate(true)
		for slot: Variant in (record.outfit.slots as Dictionary):
			record.outfit.slots[slot] = {"item": "", "dye": ""}
	if shot.has("build"):
		var b: Vector2 = shot.build
		record = record.duplicate(true)
		record["build"] = {"brawn": b.x, "girth": b.y}
	var eq := Armour.equipment_with(shot.get("pieces", []) as Array, shot.get("hidden", []) as Array)
	var p := _preview
	p.set_game_profile(GiantPreview.stage_profile(int(shot.get("stage", 1))))
	p.world_light = not bool(shot.get("studio", false))
	p.apply_look(Armour.look_of(record, eq, ""))
	p.frame(str(shot.get("framing", "full")))
	p.turn_deg = 0.0
	if float(shot.get("turn", 0.0)) != 0.0:
		p.turn(float(shot.turn))
	if float(shot.get("zoom", 0.0)) != 0.0:
		p.zoom(float(shot.zoom))
	_pose(p, str(shot.get("clip", "")), float(shot.get("clip_s", 0.0)))
	p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	var img := p.viewport.get_texture().get_image()
	var path := out_dir.path_join("%s.png" % str(shot.name))
	if img.save_png(path) == OK:
		_written.append(path)


## A clip's frame at `t` s (the still pose without one).
static func _pose(p: GiantPreview, clip: String, t: float) -> void:
	var sk := p.model.skeleton()
	if sk == null:
		return
	var old := p.model.get_node_or_null("StillsPlayer") as AnimationPlayer
	if clip == "rest" or clip == "":
		if old != null:
			old.stop()
			p.model.remove_child(old)
			old.free()
		p.model.pose_rest()
		if clip == "":
			p.model.pose_relaxed()
		return
	var lib := SkinnedRig.clip_library()
	if lib == null or not lib.has_animation(clip):
		p.model.pose_relaxed()
		return
	var player := p.model.get_node_or_null("StillsPlayer") as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "StillsPlayer"
		p.model.add_child(player)
		player.root_node = player.get_path_to(sk.get_parent().get_parent())
		player.add_animation_library(SkinnedRig.LIBRARY, lib)
	player.play(String(SkinnedRig.LIBRARY) + "/" + clip)
	player.seek(t, true)
	player.pause()
