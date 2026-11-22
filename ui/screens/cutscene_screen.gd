class_name CutsceneScreen
extends UiScreen
## The cutscene player (A4): ScreenStack SCREENS["cutscene"], opened with {"cutscene": a cutscene record id, "level":
## the level it plays in (the world)}. A reusable player of data: the record's shot list (CutsceneRules - camera
## travels, actors' clips and places, subtitles, sound cues, shakes, dust, fades and a title card, all in ticks)
## played one tick a physics frame (60 a second; deterministic: a --write-movie run at a fixed fps films the same
## frames every time). It is a screen so the stack pauses the world, hides the HUD and shows its footer, which here is
## the skip hint with the device's glyphs ("A / B: skip" or "Enter / Esc: skip"); any confirm or cancel (Enter,
## Space, Esc, pad A, B or Start) skips at once. Its 3D part (a camera, the actors, the dust) lives under the level
## (a Node3D running while paused) and is freed when it ends; the camera that was current comes back.
## Before its first tick it streams the world round the record's `focus` (WorldRoot's streamer: the ring loaded,
## behind black), so every shot stands on loaded ground. close() returns {"cutscene", "skipped", "ticks"}.
##
##   actors  "stoneback": his model (StonebackRig: StonebackRig.pose(clip, t)); "giant": the player's own giant -
##           the giant model with the session's look (Appearance.to_look), at the stage the record names, in its idle;
##           "villager": one of the people (PersonModel, the villager role's `variant`) in its clip (idle, walk,
##           run, flee, cower)

const SKIP_ACTIONS := ["ui_accept", "ui_cancel", "pause", "interact", "jump", "dodge"]
const LETTERBOX_PX := 74.0
const GIANT_MODEL := "res://scenes/player/giant_model.tscn"

var rec: Dictionary = {}
var cutscene_id := ""
## The timeline's tick (0 at its start; -1 while the world still streams).
var tick := -1
var skipped := false
var level: Node = null
var camera: Camera3D = null
var stage: Node3D = null
## Actor id -> its node (a holder Node3D placed and turned; its model under it).
var actors: Dictionary = {}
var cues_played: Array[String] = []
var dust_raised := 0
var _prev_camera: Camera3D = null
var _subtitle: Label
var _title: Label
var _sub: Label
var _fade: ColorRect
var _bars: Array[ColorRect] = []
var _stream_wait := 0
var _done := false
## The level's own giant, hidden while the cutscene plays (its actors stand in for it), and shown again after.
var _hidden_player: Node3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.offset_bottom = LETTERBOX_PX
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -LETTERBOX_PX
		add_child(bar)
		_bars.append(bar)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_subtitle = UiKit.label("", 26)
	_subtitle.name = "Subtitle"
	_subtitle.add_theme_constant_override("outline_size", 8)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.anchor_left = 0.5
	_subtitle.anchor_right = 0.5
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_left = -520
	_subtitle.offset_right = 520
	_subtitle.offset_top = -LETTERBOX_PX - 96
	_subtitle.offset_bottom = -LETTERBOX_PX - 8
	add_child(_subtitle)
	var card := VBoxContainer.new()
	card.name = "TitleCard"
	# (in the picture's upper third: the last shot's giants stand in its middle)
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_top = LETTERBOX_PX + 34.0
	card.offset_bottom = LETTERBOX_PX + 190.0
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	_title = UiKit.label("", 76, Color(0.96, 0.90, 0.74))
	_title.add_theme_constant_override("outline_size", 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_title)
	_sub = UiKit.label("", 30, Color(0.86, 0.80, 0.66))
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_sub)


## The skip hint with the device's glyphs (the stack's footer).
func nav_hint(pad: bool) -> String:
	return "A / B: skip" if pad else "Enter / Esc: skip"


func on_open() -> void:
	cutscene_id = str(args.get("cutscene", ExpansionState.INTRO_ID))
	rec = GameData.get_record(cutscene_id)
	level = args.get("level") as Node
	if level == null and is_inside_tree():
		level = get_tree().current_scene
	if rec.is_empty() or level == null or not level.is_inside_tree():
		_finish(true)
		return
	stage = Node3D.new()
	stage.name = "Cutscene"
	stage.process_mode = Node.PROCESS_MODE_ALWAYS
	level.add_child(stage)
	_prev_camera = get_viewport().get_camera_3d()
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and p.visible and level.is_ancestor_of(p):
		_hidden_player = p
		p.visible = false
	camera = Camera3D.new()
	camera.name = "CutsceneCamera"
	camera.near = 0.2
	camera.far = 4000.0
	stage.add_child(camera)
	camera.make_current()
	for a: Variant in rec.get("actors", []):
		if typeof(a) == TYPE_DICTIONARY:
			_spawn_actor(a)
	_apply(0)
	_update_ui()


func first_focus() -> Control:
	return null


func cancel() -> void:
	skip()


## Ends it at once (any confirm or cancel).
func skip() -> void:
	_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	if _done or stack == null or stack.top() != self:
		return
	for a: String in SKIP_ACTIONS:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			skip()
			return


func _physics_process(_delta: float) -> void:
	if _done or rec.is_empty():
		return
	if tick < 0:
		if _streamed() or _stream_wait > 600:
			tick = 0
			_fire(0, 1)
			# (the video export cuts the movie from this frame: tools/export_cinematic.sh)
			print("CUTSCENE_START %s frame %d" % [cutscene_id, Engine.get_frames_drawn()])
		else:
			_stream_wait += 1
		return
	var before := tick
	tick += 1
	_fire(before + 1, tick + 1)
	if tick >= CutsceneRules.ticks_of(rec):
		_finish(false)
		return
	_apply(tick)


func _process(_delta: float) -> void:
	_update_ui()


# --------------------------------------------------------------------------- the world

## Streams the ring round the record's focus (a world level): true once its chunks are loaded (or there is no
## streamer: a plain level).
func _streamed() -> bool:
	var f: Variant = rec.get("focus")
	var w := level as WorldRoot
	if w == null or w.streamer == null or typeof(f) != TYPE_ARRAY or (f as Array).size() != 3:
		return true
	var at := Vector3(float(f[0]), 0.0, float(f[2]))
	w.streamer.load_ring_slice(at)
	for id in w.streamer.ring_ids(at):
		if not w.streamer.is_loaded(id):
			return false
	return true


func _spawn_actor(a: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Actor_" + str(a.get("id", "actor"))
	stage.add_child(holder)
	match str(a.get("kind", "")):
		"stoneback":
			var rig := StonebackRig.new()
			rig.name = "Stoneback"
			holder.add_child(rig)
			rig.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
			holder.set_meta("rig", rig)
		"giant":
			var scene := load(GIANT_MODEL) as PackedScene
			var model := scene.instantiate() as GiantModel if scene != null else null
			if model != null:
				holder.add_child(model)
				var character: Dictionary = GameSession.character
				var look := Appearance.to_look(character.get("appearance", {}) if typeof(character.get("appearance")) == TYPE_DICTIONARY
					else {}, str(character.get("ancestry", "")))
				if GiantLook.materials(model).is_empty():
					GiantLook.build_materials(model, model.index, "auto")
				GiantLook.apply(model, model.index, look)
				model.play_idle()
				var prof := TitanDuel.profile(int(a.get("stage", 1)))
				holder.scale = Vector3.ONE * GiantPreview.stage_scale(prof)
				holder.set_meta("model", model)
		"villager":
			var person := PersonModel.acquire("villager", str(a.get("variant", "")))
			if person != null:
				holder.add_child(person)
				holder.scale = Vector3.ONE * person.natural_scale()
				holder.set_meta("person", person)
	actors[str(a.get("id", ""))] = holder
	holder.set_meta("spec", a)


func _apply(t: int) -> void:
	var cam := CutsceneRules.camera_at(rec, t)
	if not cam.is_empty() and camera != null:
		var at: Vector3 = cam.at
		var look: Vector3 = cam.look
		camera.fov = float(cam.fov)
		if at.distance_to(look) > 0.01:
			camera.global_transform = Transform3D(Basis(), at).looking_at(look, Vector3.UP)
	for id: String in actors:
		var holder := actors[id] as Node3D
		var spec: Dictionary = holder.get_meta("spec")
		var st := CutsceneRules.actor_at(spec, t)
		holder.visible = bool(st.visible)
		var at: Vector3 = st.at
		if bool(spec.get("on_ground", false)) and level is WorldRoot:
			var gy := (level as WorldRoot).height_at(at)
			if not is_nan(gy):
				at.y = gy
		holder.global_position = at
		holder.rotation = Vector3(0.0, deg_to_rad(float(st.yaw)), 0.0)
		var rig := holder.get_meta("rig") as StonebackRig if holder.has_meta("rig") else null
		if rig != null and str(st.clip) != "" and rig.model != null:
			var length := rig.clip_length(str(st.clip))
			var ct := float(st.clip_s)
			ct = fposmod(ct, maxf(length, 0.01)) if bool(st.get("loop", false)) else clampf(ct, 0.0, length)
			rig.pose(str(st.clip), ct)
		var person := holder.get_meta("person") as PersonModel if holder.has_meta("person") else null
		if person != null and str(st.clip) != "" and person.player() != null:
			var ap := person.player()
			var full := StringName(String(PersonModel.LIBRARY) + "/" + str(st.clip))
			if ap.has_animation(full):
				if ap.current_animation != String(full):
					ap.play(full)
				ap.seek(fposmod(float(st.clip_s), maxf(ap.get_animation(full).length, 0.01)), true)


## The cues, shakes and dust whose tick lies in [t0, t1).
func _fire(t0: int, t1: int) -> void:
	for c: Dictionary in CutsceneRules.due(rec, "cues", t0, t1):
		cues_played.append(str(c.cue))
		if Audio != null and Audio.has_method("play"):
			Audio.play(str(c.cue), Vector3.INF, {"volume_db": float(c.get("volume_db", 0.0)), "reason": "cutscene"})
	for d: Dictionary in CutsceneRules.due(rec, "dust", t0, t1):
		if DustBurst.puff(stage, CutsceneRules.vec3(d.get("at")), float(d.get("size", 8.0)), int(d.get("count", 20)),
				float(d.get("speed", 8.0))) != null:
			dust_raised += 1


func _update_ui() -> void:
	if rec.is_empty() or _subtitle == null:
		return
	var t := maxi(tick, 0)
	_subtitle.text = CutsceneRules.line_at(rec, t) if tick >= 0 else ""
	var fade := 1.0 if tick < 0 else CutsceneRules.fade_at(rec, t)
	_fade.color.a = fade
	var ta := CutsceneRules.title_at(rec, t)
	var card: Dictionary = rec.get("title", {}) if typeof(rec.get("title")) == TYPE_DICTIONARY else {}
	_title.text = str(card.get("text", ""))
	_sub.text = str(card.get("sub", ""))
	_title.modulate.a = ta
	_sub.modulate.a = ta


## The subtitle shown now (tests).
func subtitle() -> String:
	return _subtitle.text if _subtitle != null else ""


func _finish(was_skipped: bool) -> void:
	if _done:
		return
	_done = true
	skipped = was_skipped
	print("CUTSCENE_END %s frame %d%s" % [cutscene_id, Engine.get_frames_drawn(), " skipped" if was_skipped else ""])
	if _prev_camera != null and is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree():
		_prev_camera.make_current()
	if _hidden_player != null and is_instance_valid(_hidden_player):
		_hidden_player.visible = true
	for id: String in actors:
		var h := actors[id] as Node3D
		var person := h.get_meta("person") as PersonModel if is_instance_valid(h) and h.has_meta("person") else null
		if person != null:
			PersonModel.release(person)
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = null
	actors.clear()
	var w := level as WorldRoot if level != null and is_instance_valid(level) else null
	if w != null and w.streamer != null and w.player() != null:
		w.streamer.focus(w.player().global_position)
	close({"cutscene": cutscene_id, "skipped": was_skipped, "ticks": maxi(tick, 0)})
