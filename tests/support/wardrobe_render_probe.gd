extends Node
## The wardrobe, rendered (P54; plan M11 §2.6, §3.7): tests/slow/test_wardrobe_render.gd runs this scene
## (tests/support/wardrobe_render_probe.tscn) in a child Godot under Xvfb with the Compatibility renderer:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/wardrobe_render_probe.tscn [-- --out=/abs/folder]
##
## The check (default): GiantPreview at 320x240 in the world's light shows the fullest slot look (the huscarl's
## outfit: a garment in every one of the ten slots, the three accessories, long hair and a full beard) from the front
## and from behind. Each garment and accessory mesh is drawn in a flat colour of its own (unshaded, the look's own
## skeleton and pose) and the frame is drawn twice with the camera moved by half a millimetre: where two surfaces
## share a depth (z-fighting) the colour under a pixel flips although its neighbours keep theirs. It reports per view
## the share of the giant's pixels that flip so (`flicker`), which garments show (`seen`), the draw calls and the
## primitives of the view (the renderer's own counters), and GiantLook.validate(). One line:
##   WARDROBE_RENDER {"views": {name: {"flicker", "pixels", "seen": [...], "draws", "primitives"}}, "validate": [...],
##                    "meshes": n, "adapter": ...}
## P57 (plan M11 §3.10 item 4): with --stack=N [--seed=S] the stack check instead - N random slot looks (half as the
## creator's Randomize dresses him, half with nearly every slot filled), each in three poses (standing relaxed, the run
## clip at mid-stride, the roar) from the front, behind or three-quarters in turn, measured as above in the world's
## light, with every pose and view at most STACK_VIEWS a look; and a positive control: the fullest look with a copy of
## one garment drawn over it, pushed out along its normals by CONTROL_PUSH_M (within the depth buffer's step at that
## distance), whose flicker must rise. One line:
##   WARDROBE_STACK {"looks", "views", "worst": {"patch", "clustered", "changed", "pixels", "look", "pose"}, "over": n,
##                   "floor": PATCH_FLOOR, "flicker_worst", "control": {"patch", "flicker", ..., "push_m"}, "ms", "adapter"}
## The stack check's measure is flicker()'s "patch": the changed pixels with at least CLUSTER changed neighbours (z-fighting
## interleaves two surfaces in patches; the fullest look's "flicker", interior pixels alone, missed the control's speckle).
## P57 (plan M11 §3.10 item 5, §2.12's rows for the giant): with --budget the measures instead (no check; run it at the
## window's size, 1920x1080 for the far rows): for the Wanderer and the fullest look of the data (the outfit that fills
## the most slots, an accessory in every accessory slot) the meshes drawn, the giant's own draw calls and primitives
## at 4, 30, 60, 121, 130, 151 and 200 m (the preview's viewport at the window's size: the LODs follow the pixels), the
## mesh buffers held (GiantModel.resident_bytes, the recent parts apart), the texture memory the giant's maps take (the
## renderer's monitor before the first giant and after both looks), and the crop's shell stack at 30, 60 and 120 m.
##   WARDROBE_BUDGET {"looks": {name: {"meshes", "draws", "primitives": {m: n}, "mesh_bytes"}}, "texture_bytes",
##                    "crop": {m: n}, "size", "adapter"}
## With --review the probe draws instead the look sheets a reviewer reads (no check): for every outfit (and the
## fullest look with its accessories) front, side and back in the world's light and in the creator's at stage 1, and
## for the fullest look also at stage 6 and at build -1 and +1, each sheet one PNG in --out.

const PREFIX := "WARDROBE_RENDER "
const STACK_PREFIX := "WARDROBE_STACK "
const BUDGET_PREFIX := "WARDROBE_BUDGET "
## The budget's distances (m from the giant's middle, stage 1).
const BUDGET_DISTANCES := [4.0, 30.0, 60.0, 121.0, 130.0, 151.0, 200.0]
## The stack check's floor: the share of the giant's pixels a nudge may flip (the fullest look's own check's).
const MAX_FLICKER := 0.002
## A changed pixel with at least this many of its eight neighbours changed is a z-fighting patch's (flicker()).
const CLUSTER := 3
## The stack check's poses: [name, clip ("" for the relaxed pose), the clip's time (s)], and its views (yaw).
const STACK_POSES := [["relaxed", "", 0.0], ["run", "run", 0.25], ["roar", "roar", 0.6]]
const STACK_YAWS := [0.0, 180.0, 35.0]
## The stack check's floor: the share of the giant's pixels that may change in patches (flicker()'s "patch") when the
## camera moves by half a millimetre. A look without z-fighting measured 0 in the first runs; the control's boots 0.003.
const PATCH_FLOOR := 0.0005
## The positive control's push (m): about an eighth of the 24-bit depth buffer's step at the full framing's distance
## (0.04 mm pushed the copy clear of its original at most pixels; 4 mm everywhere).
const CONTROL_PUSH_M := 0.00001
const STACK_WATCHDOG_S := 480.0
const TILE := Vector2i(320, 240)
const REVIEW_TILE := Vector2i(300, 420)
const WATCHDOG_S := 200.0
const FULLEST := "outfit.huscarl"
const ACCESSORIES := {"neck": "accessory.gilded_torc", "arm_ring": "accessory.iron_arm_ring", "belt": "accessory.drinking_horn"}
## The camera's nudge between the two frames of a view (metres, stage 1).
const NUDGE_M := 0.0005
## Two colours are one garment's when they differ by less than this (sum over the channels, 0-3).
const SAME := 0.02
## A pixel is a garment's flat colour when it lies within this of it (the frame's own rounding).
const MATCH := 0.08
## The flat colours, far apart from one another and from the backdrop's sky and ground.
const PALETTE := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0), Color(1, 0, 1), Color(0, 1, 1),
	Color(1, 0.5, 0), Color(0.5, 0, 1), Color(0, 0.5, 0), Color(0.5, 0, 0), Color(0, 0, 0.5), Color(1, 1, 1),
	Color(0.5, 0.5, 0), Color(0, 0.5, 0.5), Color(0.5, 0, 0.5), Color(1, 0.5, 0.5)]

var _p: GiantPreview
var _out := ""
var _review := false
var _control_push := CONTROL_PUSH_M
var _giant_textures := {}


func _ready() -> void:
	var stack_n := 0
	var seed := 57
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stack="):
			stack_n = int(arg.substr(8))
		elif arg.begins_with("--seed="):
			seed = int(arg.substr(7))
		elif arg.begins_with("--control-push="):
			_control_push = float(arg.substr(15))
	get_tree().create_timer(STACK_WATCHDOG_S if stack_n > 0 else WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "the probe timed out"}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg == "--review":
			_review = true
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	var size := REVIEW_TILE if _review else TILE
	if OS.get_cmdline_user_args().has("--budget"):
		_giant_textures = await _texture_bytes_of_the_giant()
	_p = GiantPreview.new()
	_p.still = true
	_p.stretch = false
	_p.custom_minimum_size = Vector2(size)
	_p.size = Vector2(size)
	add_child(_p)
	_p.viewport.size = size
	_p.viewport.msaa_3d = Viewport.MSAA_DISABLED
	_p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if stack_n > 0:
		get_tree().process_frame.connect(func() -> void: _stack_run(stack_n, seed), CONNECT_ONE_SHOT)
		return
	if OS.get_cmdline_user_args().has("--budget"):
		_p.viewport.size = DisplayServer.window_get_size()   # the window's pixels: the LODs follow them
		get_tree().process_frame.connect(_budget_run, CONNECT_ONE_SHOT)
		return
	get_tree().process_frame.connect(_review_run if _review else _run, CONNECT_ONE_SHOT)


func _draw_frame() -> Image:
	for i in 2:
		await RenderingServer.frame_post_draw
	return _p.viewport.get_texture().get_image()


## The fullest slot look's record: the huscarl's outfit, the three accessories, long hair, a full beard.
static func fullest_record() -> Dictionary:
	var r := Appearance.with_outfit(Appearance.preset_record("appearance_preset.wanderer"), FULLEST)
	for slot: String in ACCESSORIES:
		r.outfit.accessories[slot] = ACCESSORIES[slot]
	r.outfit.dyes = {"cloth": "dye.woad_blue", "leather": "dye.walnut", "metal": "metal.steel"}
	return r


func _run() -> void:
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "views": {}, "validate": []}
	_p.world_light = true
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var look := Appearance.to_look(fullest_record())
	_p.apply_look(look)
	report.validate = Array(GiantLook.validate(_p.model, _p.model.index, look))
	var shown: Array = []
	for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
		if mi.visible and mi.is_visible_in_tree():
			shown.append(mi)
	report["meshes"] = shown.filter(func(mi: MeshInstance3D) -> bool: return mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY).size()
	for view: String in ["front", "back"]:
		_p.frame("full")
		_p.turn(0.0 if view == "front" else 180.0)
		var counters: Dictionary = (await _counters()) if view == "front" else report.views.front.duplicate()
		counters = {"draws": counters.draws, "primitives": counters.primitives}
		var colours := _flat(shown)
		var a: Image = await _draw_frame()
		_p.camera.position += _p.camera.transform.basis.x * NUDGE_M
		var b: Image = await _draw_frame()
		_unflat(shown)
		var m := flicker(a, b)
		m["seen"] = _seen(a, colours)
		m.merge(counters)
		report.views[view] = m
		if _out != "":
			a.save_png(_out.path_join("wardrobe_ids_%s.png" % view))
	print(PREFIX + JSON.stringify(report))
	get_tree().quit(0)


# ------------------------------------------------------------------------------------------------ the budget

func _budget_run() -> void:
	var report := {"looks": {}, "size": [_p.viewport.size.x, _p.viewport.size.y], "adapter": RenderingServer.get_video_adapter_name()}
	_p.world_light = true
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var wanderer := Appearance.preset_record("appearance_preset.wanderer")
	for look: Array in [["wanderer", wanderer], ["fullest", random_fullest(wanderer)]]:
		_p.apply_look(Appearance.to_look(look[1]))
		var shown := 0
		for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree() and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				shown += 1
		var prims := {}
		var draws := 0
		for d: float in BUDGET_DISTANCES:
			_at_distance(d)
			var c: Dictionary = await _counters()
			prims[str(int(d))] = c.primitives
			if d == 4.0:
				draws = c.draws
		report.looks[look[0]] = {"meshes": shown, "draws": draws, "primitives": prims, "mesh_bytes": _p.model.resident_bytes(),
			"garments": Appearance.record_garments(look[1]).size()}
	report["texture_bytes"] = _giant_textures
	# the far primitives by mesh (the Wanderer at 121 m): each shown mesh hidden in turn
	_p.apply_look(Appearance.to_look(wanderer))
	_at_distance(121.0)
	var whole: Dictionary = await _counters()
	var by_mesh := {}
	for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		mi.visible = false
		var less: Dictionary = await _counters()
		mi.visible = true
		by_mesh[str(mi.name)] = int(whole.primitives) - int(less.primitives)
	report["far_by_mesh"] = by_mesh
	report["recent_part_bytes"] = GiantModel.recent_bytes()
	# the crop (a shell style): its stack's primitives at three distances
	var crop := OptionRows.with_value(wanderer, "hair.style", "hair.crop")
	crop = OptionRows.with_value(crop, "beard.style", "beard.none")
	_p.apply_look(Appearance.to_look(crop))
	var crop_prims := {}
	for d: float in [30.0, 60.0, 120.0]:
		_at_distance(d)
		var with_hair: Dictionary = await _counters()
		crop_prims[str(int(d))] = with_hair.primitives
	report["crop"] = crop_prims
	print(BUDGET_PREFIX + JSON.stringify(report))
	get_tree().quit(0)


## The renderer's texture memory the giant's maps take, by tier: a bare model's materials built (nothing drawn yet but
## the textures made) against the monitor before; the web tier first, then the hi tier's extra.
func _texture_bytes_of_the_giant() -> Dictionary:
	var out := {}
	await get_tree().process_frame
	var before := int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	for tier: String in ["web", "hi"]:
		var m := GiantPreview.MODEL.instantiate() as GiantModel
		add_child(m)
		m.visible = false
		GiantLook.build_materials(m, m.index, tier)
		GiantLook.apply(m, m.index, Appearance.to_look(random_fullest(Appearance.preset_record("appearance_preset.wanderer"))))
		await get_tree().process_frame
		await get_tree().process_frame
		out[tier] = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) - before
		m.free()
	return out


## The fullest look of the data (the outfit that fills the most slots, an accessory in every accessory slot).
static func random_fullest(base: Dictionary) -> Dictionary:
	var best := ""
	var most := -1
	for id in Appearance.option_ids("outfit"):
		var n := Appearance.record_garments(Appearance.with_outfit(base, id)).size()
		if n > most:
			most = n
			best = id
	var rec := Appearance.with_outfit(base, best)
	for slot: String in Appearance.ACCESSORY_SLOTS:
		for id in Appearance.option_ids("accessory"):
			if str(Appearance.option(id).get("slot", "")) == slot:
				rec = OptionRows.with_value(rec, "outfit.accessories." + slot, id)
				break
	return rec


## The camera `d` metres from the giant's middle, three-quarter from the front, looking at him.
func _at_distance(d: float) -> void:
	_p.frame("full")
	_p.camera.far = 4000.0
	var target := Vector3(0.0, 1.85, 0.0)
	var dir := (_p.camera.position - target).normalized()
	_p.camera.position = target + dir * d
	_p.camera.look_at(target, Vector3.UP)


# ------------------------------------------------------------------------------------------------ the stack check

## N random slot looks in three poses, and the positive control (see the header).
func _stack_run(n: int, seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_p.world_light = true
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var report := {"looks": 0, "views": 0, "over": 0, "floor": PATCH_FLOOR, "worst": {"patch": 0.0}, "flicker_worst": 0.0,
		"adapter":
		RenderingServer.get_video_adapter_name(), "slots_worn": 0}
	var player := _pose_player()
	for i in n:
		var rec := random_stacked(rng, i % 2 == 1)
		_p.apply_look(Appearance.to_look(rec))
		report.slots_worn = int(report.slots_worn) + Appearance.record_garments(rec).size()
		for k in STACK_POSES.size():
			var pose: Array = STACK_POSES[k]
			_pose(player, str(pose[1]), float(pose[2]))
			var m := await _flicker_of_view(float(STACK_YAWS[(i + k) % STACK_YAWS.size()]))
			report.views = int(report.views) + 1
			report.flicker_worst = maxf(float(report.flicker_worst), float(m.flicker))
			if float(m.patch) > PATCH_FLOOR:
				report.over = int(report.over) + 1
			if float(m.patch) >= float(report.worst.patch):
				report.worst = {"patch": m.patch, "clustered": m.clustered, "changed": m.changed, "pixels": m.pixels, "look": i,
					"pose": pose[0],
					"garments": Appearance.record_garments(rec).map(func(g: Variant) -> String: return Appearance.garment_id(g))}
		report.looks = int(report.looks) + 1
	# the positive control: a garment drawn twice, the copy pushed out by less than the depth buffer's step
	_pose(player, "", 0.0)
	_p.apply_look(Appearance.to_look(fullest_record()))
	var copy := _coincident_copy(await _most_seen_garment())
	report["control"] = {"push_m": _control_push, "garment": str(copy.get_meta("of", "")) if copy != null else ""}
	if copy != null:
		var m := await _flicker_of_view(0.0, "wardrobe_stack_control.png")
		report.control.merge(m)
		copy.queue_free()
	report["ms"] = Time.get_ticks_msec() - t0
	print(STACK_PREFIX + JSON.stringify(report))
	get_tree().quit(0)


## A random slot look: as the creator's Randomize dresses him (an outfit, then slots swapped, filled and emptied, the
## accessories), or `dense`: nearly every slot filled with one of its pieces, every accessory slot too.
static func random_stacked(rng: RandomNumberGenerator, dense: bool) -> Dictionary:
	var base := Appearance.preset_record("appearance_preset.wanderer")
	var r: Dictionary
	if not dense:
		r = OptionRows.random_record(rng, "clothing", false, "", base)
		r = OptionRows.random_record(rng, "accessories", false, "", r)
	else:
		r = base.duplicate(true)
		for slot: String in Appearance.SLOTS:
			var ids := Array(Appearance.option_ids("garment")).filter(func(id: String) -> bool:
				return str(Appearance.option(id).get("slot", "")) == slot)
			if not ids.is_empty() and rng.randf() < 0.9:
				r = OptionRows.with_value(r, "outfit.slots.%s.item" % slot, ids[rng.randi_range(0, ids.size() - 1)])
		for slot: String in Appearance.ACCESSORY_SLOTS:
			var ids := Array(Appearance.option_ids("accessory")).filter(func(id: String) -> bool:
				return str(Appearance.option(id).get("slot", "")) == slot)
			if not ids.is_empty():
				r = OptionRows.with_value(r, "outfit.accessories." + slot, ids[rng.randi_range(0, ids.size() - 1)])
	return Appearance.sanitize(r, "").record


## The model's own player of the clip library (the stack check's poses).
func _pose_player() -> AnimationPlayer:
	var sk := _p.model.skeleton()
	var lib := SkinnedRig.clip_library()
	if sk == null or lib == null:
		return null
	var player := AnimationPlayer.new()
	player.name = "StackPoses"
	_p.model.add_child(player)
	player.root_node = player.get_path_to(sk.get_parent().get_parent())
	player.add_animation_library(SkinnedRig.LIBRARY, lib)
	return player


## The clip `clip` held at `at` seconds (the relaxed pose for "").
func _pose(player: AnimationPlayer, clip: String, at: float) -> void:
	if player == null or clip == "" or not player.has_animation(String(SkinnedRig.LIBRARY) + "/" + clip):
		if player != null:
			player.stop()
		_p.model.pose_rest()
		_p.model.pose_relaxed()
		return
	player.play(String(SkinnedRig.LIBRARY) + "/" + clip)
	player.seek(at, true)
	player.pause()
	_p.model.skeleton().force_update_all_bone_transforms()


## The flicker measure of the whole giant from `yaw`, every shown garment and accessory in a flat colour.
func _flicker_of_view(yaw: float, save_as := "") -> Dictionary:
	_p.frame("full")
	_p.turn(yaw)
	var shown: Array = []
	for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
				and not mi.has_meta("of"):
			shown.append(mi)
	_flat(shown)
	var a: Image = await _draw_frame()
	_p.camera.position += _p.camera.transform.basis.x * NUDGE_M
	var b: Image = await _draw_frame()
	_unflat(shown)
	if _out != "" and save_as != "":
		a.save_png(_out.path_join(save_as))
	return flicker(a, b)


## The shown garment that covers the most of the giant's pixels from the front (the control's: the most pixels to fight).
func _most_seen_garment() -> MeshInstance3D:
	_p.frame("full")
	_p.turn(0.0)
	var shown: Array = []
	for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			shown.append(mi)
	var colours := _flat(shown)
	var img: Image = await _draw_frame()
	_unflat(shown)
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			for k: String in colours:
				var c: Color = colours[k]
				if absf(p.r - c.r) + absf(p.g - c.g) + absf(p.b - c.b) < MATCH:
					counts[k] = int(counts.get(k, 0)) + 1
					break
	var best := ""
	for k: String in counts:
		if k.begins_with("Garment_") and (best == "" or int(counts[k]) > int(counts[best])):
			best = k
	return _p.model.find_child(best, true, false) as MeshInstance3D if best != "" else null


## The positive control's copy: the garment mesh `mi` drawn again on the same skeleton in a flat colour of its
## own, pushed out along its normals by CONTROL_PUSH_M (--control-push= for a trial). Null without a garment.
func _coincident_copy(mi: MeshInstance3D) -> MeshInstance3D:
	if mi != null:
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.skin = mi.skin
		copy.set_meta("of", str(mi.name))
		mi.get_parent().add_child(copy)
		copy.transform = mi.transform
		copy.skeleton = copy.get_path_to(mi.get_node(mi.skeleton))
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, fog_disabled;\nuniform float push = 0.0;\n" + \
			"void vertex() { VERTEX += NORMAL * push; }\nvoid fragment() { ALBEDO = vec3(1.0, 0.0, 1.0); }\n"
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("push", _control_push)
		copy.material_override = mat
		return copy
	return null


## The giant's own draw calls and primitives in the view's main pass, as the renderer counts them: the frame with the
## model less the frame without it (the look as drawn, its own materials; shadows are counted apart, the proxy's).
func _counters() -> Dictionary:
	var rid := _p.viewport.get_viewport_rid()
	var info := func() -> Vector2i:
		return Vector2i(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	await _draw_frame()
	var with_model: Vector2i = info.call()
	_p.model.visible = false
	await _draw_frame()
	var without: Vector2i = info.call()
	_p.model.visible = true
	return {"draws": with_model.x - without.x, "primitives": with_model.y - without.y}


## Every garment and accessory mesh in a flat colour of its own (the body, hair and eyes black): {mesh name: colour}.
func _flat(shown: Array) -> Dictionary:
	var out := {}
	var i := 0
	# the flat colours come out as they are: no fog, no tonemapping
	_p.environment.fog_enabled = false
	_p.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_p.environment.tonemap_exposure = 1.0
	for mi: MeshInstance3D in shown:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cat := str((_p.model.index.meshes.get(str(mi.name), {}) as Dictionary).get("category", ""))
		m.disable_fog = true
		var c := Color.BLACK
		if cat in ["garment", "accessory"]:
			c = PALETTE[i % PALETTE.size()]
			i += 1
			out[str(mi.name)] = c
		m.albedo_color = c
		mi.set_meta("wardrobe_probe_material", mi.material_override)
		mi.material_override = m
	return out


func _unflat(shown: Array) -> void:
	_p.environment.fog_enabled = _p.world_light
	for mi: MeshInstance3D in shown:
		mi.material_override = mi.get_meta("wardrobe_probe_material")
		mi.remove_meta("wardrobe_probe_material")


## The garments whose colour covers at least a few pixels of the frame.
static func _seen(img: Image, colours: Dictionary) -> Array:
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			for k: String in colours:
				var c: Color = colours[k]
				if absf(p.r - c.r) + absf(p.g - c.g) + absf(p.b - c.b) < MATCH:
					counts[k] = int(counts.get(k, 0)) + 1
					break
	var out: Array = []
	for k: String in counts:
		if int(counts[k]) >= 4:
			out.append(k)
	out.sort()
	return out


## The z-fighting measure of two frames a nudge apart: the share of the giant's pixels (not the backdrop) whose colour
## changes although the colour of each of their four neighbours in the first frame is their own (an interior pixel of
## a surface: a moved silhouette changes edge pixels only).
static func flicker(a: Image, b: Image) -> Dictionary:
	var w := a.get_width()
	var h := a.get_height()
	var bg := a.get_pixel(0, 0)
	var pixels := 0
	var flips := 0
	var changed := 0
	var moved := PackedByteArray()
	moved.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var p := a.get_pixel(x, y)
			if _d(p, bg) < SAME:
				continue
			pixels += 1
			if _d(p, b.get_pixel(x, y)) < SAME:
				continue
			changed += 1
			moved[y * w + x] = 1
			if _d(p, a.get_pixel(x - 1, y)) < SAME and _d(p, a.get_pixel(x + 1, y)) < SAME \
					and _d(p, a.get_pixel(x, y - 1)) < SAME and _d(p, a.get_pixel(x, y + 1)) < SAME:
				flips += 1
	# P57: z-fighting changes pixels in patches (two surfaces interleaved a pixel or two at a time), a moved silhouette
	# along a line: a changed pixel with at least CLUSTER of its eight neighbours changed too is a patch's
	var clustered := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if moved[y * w + x] == 0:
				continue
			var n := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if (dx != 0 or dy != 0) and moved[(y + dy) * w + x + dx] != 0:
						n += 1
			if n >= CLUSTER:
				clustered += 1
	return {"pixels": pixels, "flicker": float(flips) / maxf(1.0, float(pixels)), "flips": flips,
		"changed": changed, "clustered": clustered, "patch": float(clustered) / maxf(1.0, float(pixels))}


static func _d(p: Color, q: Color) -> float:
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)


# ------------------------------------------------------------------------------------------------ the review sheets
func _review_run() -> void:
	var looks := {}
	for id: String in Appearance.option_ids("outfit"):
		var r := Appearance.with_outfit(Appearance.preset_record("appearance_preset.wanderer"), id)
		r.outfit.dyes = {"cloth": "dye.madder", "leather": "dye.walnut", "metal": "metal.iron"}
		looks[id.trim_prefix("outfit.")] = r
	looks["fullest"] = fullest_record()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--looks="):
			only = arg.substr(8)
	for name: String in looks:
		if only != "" and not name in only.split(","):
			continue
		var tiles: Array = []
		for world: bool in [true, false]:
			for yaw: float in [20.0, 90.0, 180.0]:
				tiles.append(await _tile(looks[name], world, yaw, 1, Vector2.ZERO))
		_save_sheet(tiles, 3, "sheet_%s.png" % name)
		if OS.get_cmdline_user_args().has("--closeups"):
			var close: Array = []
			for f: String in ["chest", "face", "back_design"]:
				close.append(await _tile(looks[name], true, 0.0, 1, Vector2.ZERO, f))
			for f: String in ["arms", "chest", "hair"]:
				close.append(await _tile(looks[name], false, 0.0 if f != "chest" else 150.0, 1, Vector2.ZERO, f))
			_save_sheet(close, 3, "sheet_%s_close.png" % name)
		if OS.get_cmdline_user_args().has("--build-close"):
			var bc: Array = []
			for b: Vector2 in [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]:
				bc.append(await _tile(looks[name], false, 0.0, 1, b, "back_design"))
			for b: Vector2 in [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]:
				bc.append(await _tile(looks[name], false, 0.0, 1, b, "arms"))
			_save_sheet(bc, 3, "sheet_%s_build_close.png" % name)
		if name == "fullest" or only != "":
			var extra: Array = []
			for b: Vector2 in [Vector2(-1, -1), Vector2(1, 1)]:
				for yaw: float in [20.0, 180.0]:
					extra.append(await _tile(looks[name], true, yaw, 1, b))
			for yaw: float in [0.0, 180.0]:
				extra.append(await _tile(looks[name], true, yaw, 6, Vector2.ZERO, "game"))
			_save_sheet(extra, 3, "sheet_%s_build_stage.png" % name)
	print(PREFIX + JSON.stringify({"review": _out}))
	get_tree().quit(0)


func _tile(record: Dictionary, world: bool, yaw: float, stage: int, build: Vector2, framing := "full") -> Image:
	var r := record.duplicate(true)
	r.build = {"brawn": build.x, "girth": build.y}
	_p.world_light = world
	_p.set_game_profile(GiantPreview.stage_profile(stage))
	_p.apply_look(Appearance.to_look(r))
	_p.frame(framing)
	_p.turn(yaw)
	return await _draw_frame()


func _save_sheet(tiles: Array, cols: int, file: String) -> void:
	if _out == "" or tiles.is_empty():
		return
	var tw := (tiles[0] as Image).get_width()
	var th := (tiles[0] as Image).get_height()
	var rows := int(ceil(tiles.size() / float(cols)))
	var sheet := Image.create(tw * cols, th * rows, false, (tiles[0] as Image).get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	sheet.save_png(_out.path_join(file))
