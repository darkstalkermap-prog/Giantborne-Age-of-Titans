extends TestSuite
## The creator's preview (P44; plan M10 §2.10): a SubViewport with its own world holding the real
## giant_model.tscn; a whole look applied in under a millisecond (headless, with its materials built); the
## framing per category (Hair from behind); Game view at the stage's camera (the game's third-person rig at
## rest, the model scaled by k, the world's light, a soldier for scale); UPDATE_WHEN_VISIBLE while open and
## UPDATE_ONCE for a portrait; the weapon at the hand bone, aimed along TipMatching.idle_grip; the title's
## buttons enabled at once headless (no warm-up), and a warm-up (forced) holding New Game until its frames are
## drawn, then freed when a game starts.

var layer: CanvasLayer
var stack: ScreenStack


func before_each() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	GiantPreview.materials_headless = false
	TitleScreen.force_warmup = false
	if is_instance_valid(stack):
		stack.close_all()
	if is_instance_valid(layer):
		layer.queue_free()
	await get_tree().process_frame


## The M10 gate's LC-1: the key light (warm, shadows) shines on the side of the giant the camera sees, from above
## and to one side, and the cool rim comes from behind him - in every framing and at every turn. Before the fix
## the lights were fixed in the world with the key behind him, so Face, Full and chest showed him in shadow.
func _assert_lit_from_the_camera_side(p: GiantPreview, what: String) -> void:
	var view := -p.camera.global_basis.z
	var flat := Vector3(view.x, 0.0, view.z).normalized()
	var key := -p.key_light.global_basis.z
	var rim := -p.rim_light.global_basis.z
	var key_flat := Vector3(key.x, 0.0, key.z).normalized()
	assert_true(key_flat.dot(flat) > 0.6, "%s: the key light shines the way the camera looks (%.2f)" % [what, key_flat.dot(flat)])
	assert_true(key_flat.dot(flat) < 0.97, "%s: from one side, not flat on (%.2f)" % [what, key_flat.dot(flat)])
	assert_true(key.y < -0.4, "%s: and from above (%.2f)" % [what, key.y])
	assert_true(Vector3(rim.x, 0.0, rim.z).normalized().dot(flat) < -0.6, "%s: the rim comes from behind him" % what)
	assert_true(p.key_light.shadow_enabled and p.key_light.light_energy > p.rim_light.light_energy, "%s: the key is the stronger, shadowed light" % what)


func test_its_own_world_the_look_the_framings_and_the_views() -> void:
	GiantPreview.materials_headless = true
	var p := GiantPreview.new()
	layer.add_child(p)
	await get_tree().process_frame
	assert_true(p.viewport.own_world_3d, "the preview has its own world")
	assert_true(p.viewport.world_3d != get_viewport().world_3d, "not the game's")
	assert_true(p.model is GiantModel and p.model.scene_file_path == "res://scenes/player/giant_model.tscn",
		"the same giant_model.tscn the game draws")
	assert_eq(p.viewport.render_target_update_mode, SubViewport.UPDATE_WHEN_VISIBLE, "it draws while visible")
	assert_eq(p.process_mode, Node.PROCESS_MODE_ALWAYS, "and runs while the tree is paused")
	assert_eq(GiantLook.materials(p.model).size(), (p.index().meshes as Dictionary).size(), "every mesh has its material")
	var look := Appearance.to_look(Appearance.preset_record("storm_herald"), "")
	var best := INF
	for i in 3:
		best = minf(best, p.apply_look(look))
	assert_true(best < 1.0, "a whole look is applied in under 1 ms (%.3f ms)" % best)
	assert_eq(GiantLook.validate(p.model, p.index(), look), PackedStringArray(), "validate() is empty")
	var shown_hair := GiantLook.mesh_node(p.model, p.index(), str(look.hair_mesh))
	assert_true(str(look.hair_mesh) == "" or (shown_hair != null and shown_hair.visible), "the look's hair shows")
	# Framings: Hair three-quarter from behind (+Z is behind him: the giant faces -Z), the face in front.
	p.frame("hair")
	assert_true(p.camera.position.z > 0.5, "Hair is framed from behind (camera z %.2f)" % p.camera.position.z)
	p.frame("face")
	assert_true(p.camera.position.z < -0.5 and p.camera.position.y > 3.0, "the face from the front, at eye height")
	for f: String in GiantPreview.FRAMINGS:
		p.frame(f)
		var to_target := p.framing_target(f) - p.camera.global_position
		assert_true(-p.camera.global_basis.z.dot(to_target.normalized()) > 0.99, "%s looks at its target" % f)
		_assert_lit_from_the_camera_side(p, f)
	# The lights follow a turn (the giant turns on his disc under fixed lights): the back is lit as the front is.
	p.frame("full")
	for deg: float in [90.0, 180.0, -120.0]:
		p.turn(deg - p.turn_deg)
		_assert_lit_from_the_camera_side(p, "full turned %d" % int(deg))
	# Game view: stage 4's profile, the game's camera at rest, the world's light, a soldier.
	var profile := GiantPreview.stage_profile(4)
	p.set_game_profile(profile)
	p.set_view("game")
	assert_eq(p.framing, "game", "Game view")
	var want := GiantPreview.game_camera_transform(profile)
	assert_true(p.camera.transform.origin.distance_to(want.origin) < 1e-3, "the camera sits where the game's does")
	assert_true(p.camera.transform.basis.z.dot(want.basis.z) > 0.9999, "looking the same way")
	assert_true(want.origin.z > 0.0 and want.origin.y > float(profile.camera_pivot_height_m), "behind and above him")
	assert_near(p.model.scale.x, float(profile.height_m) / GiantPreview.STAGE1_HEIGHT_M, 1e-4, "the giant at the stage's size")
	assert_near(p.camera.fov, GiantPreview.game_fov(), 1e-4, "with the game's field of view")
	assert_true(p.world_lighting(), "in the world's light")
	var soldier := p.world_root.get_node_or_null("Soldier") as Node3D
	assert_true(soldier != null and soldier.visible and soldier.get_child_count() > 0, "a soldier beside him for scale")
	p.set_view("")
	assert_false(p.world_lighting(), "back to the studio light")
	assert_near(p.model.scale.x, 1.0, 1e-6, "at stage 1")
	p.render_once()
	assert_eq(p.viewport.render_target_update_mode, SubViewport.UPDATE_ONCE, "a portrait draws once")
	p.queue_free()


func test_the_weapon_at_the_hand_and_the_category_framings() -> void:
	var c := stack.open("creator", {"context": "new_game"}) as CreatorScreen
	await get_tree().process_frame
	assert_eq(c.category_framing("Hair"), "hair", "Hair: from behind")
	assert_eq(c.category_framing("Beard"), "face", "Beard: the face")
	assert_eq(c.category_framing("Eyes"), "face", "Eyes: the face")
	for cat: String in ["Presets", "Skin", "Clothing"]:
		assert_eq(c.category_framing(cat), "full", "%s: the whole giant" % cat)
	c.show_category("Hair")
	assert_eq(c.preview.framing, "hair", "opening Hair frames it")
	var rec := GameData.get_record("weapon.club")
	assert_false(rec.is_empty(), "the club record")
	c.preview.set_weapon(rec, 1.0)
	await get_tree().process_frame
	var w := c.preview.weapon
	assert_true(w != null and w.get_parent() == c.preview.model, "the weapon is held by the model")
	var hand := c.preview.model.hand_transform(true)
	assert_true(w.global_position.distance_to(hand.origin) < 0.2, "in the right hand (%.3f m from the hand bone)" %
		w.global_position.distance_to(hand.origin))
	var grip := TipMatching.from_index(c.preview.index()).idle_grip(str(rec.get("family", "club")))
	var aim := (-w.global_basis.z).normalized()
	var want := (c.preview.model.global_basis * (grip.weapon_dir as Vector3)).normalized()
	assert_true(rad_to_deg(aim.angle_to(want)) < 1.0, "aimed along TipMatching's resting grip (%.2f deg)" %
		rad_to_deg(aim.angle_to(want)))
	c.preview.clear_weapon()
	c.close({"cancelled": true})


func test_the_preview_idles_with_the_models_clip_and_a_still_preview_stands() -> void:
	var p := GiantPreview.new()
	layer.add_child(p)
	await get_tree().process_frame
	var player := p.model.get_node_or_null(GiantModel.IDLE_PLAYER) as AnimationPlayer
	assert_true(player != null and player.is_playing(), "the model's idle player runs (GiantModel.play_idle)")
	if player == null:
		return
	assert_eq(String(player.current_animation), "giant/idle", "it plays the idle clip")
	assert_eq(player.get_animation(player.current_animation).loop_mode, Animation.LOOP_LINEAR, "as a loop")
	assert_false(p.model.has_node("AnimationTree"), "with no tree: the rig's nodes belong to the player's giant")
	var t0 := player.current_animation_position
	for i in 3:
		await get_tree().process_frame
	assert_true(player.current_animation_position > t0, "the clip advances with the frames")
	# The clip poses the skeleton: the arms hang (the rest pose is an A-pose) and the chest breathes.
	var sk := p.model.skeleton()
	var arm := sk.find_bone("upperarm_r")
	var fore := sk.find_bone("lowerarm_r")
	var spine := sk.find_bone("spine_02")
	var rest_dir := (sk.get_bone_global_rest(fore).origin - sk.get_bone_global_rest(arm).origin).normalized()
	player.seek(0.5, true)
	var breath_in := sk.get_bone_pose_rotation(spine)
	var dir := (sk.get_bone_global_pose(fore).origin - sk.get_bone_global_pose(arm).origin).normalized()
	assert_true(rad_to_deg(dir.angle_to(rest_dir)) > 15.0 and dir.y < rest_dir.y,
		"the upper arm hangs lower than at rest (%.1f deg)" % rad_to_deg(dir.angle_to(rest_dir)))
	player.seek(1.5, true)
	var breath_out := sk.get_bone_pose_rotation(spine)
	assert_true(rad_to_deg(breath_in.angle_to(breath_out)) > 1.0,
		"the spine breathes (%.2f deg between the breath's ends)" % rad_to_deg(breath_in.angle_to(breath_out)))
	p.queue_free()
	# The option check's tiles and the sheets stand still: no player, the relaxed pose.
	var still := GiantPreview.new()
	still.still = true
	layer.add_child(still)
	await get_tree().process_frame
	assert_false(still.model.has_node(GiantModel.IDLE_PLAYER), "a still preview plays no clip")
	still.queue_free()


func test_the_title_enables_at_once_headless_and_a_warm_up_holds_then_frees() -> void:
	GameSession.mode = GameSession.Mode.TITLE
	var title := stack.open("title") as TitleScreen
	assert_true(title.state().new_game, "headless: New Game is enabled at once")
	assert_eq(title.warmup_viewport(), null, "with no warm-up")
	stack.close_all()
	await get_tree().process_frame
	TitleScreen.force_warmup = true
	title = stack.open("title") as TitleScreen
	var vp := title.warmup_viewport()
	assert_true(vp != null and vp.size == Vector2i(64, 64), "a forced warm-up: a hidden 64x64 viewport")
	assert_true(vp.own_world_3d, "in its own world")
	assert_false(title.state().new_game, "New Game waits for it")
	assert_eq(title.state().note, TitleScreen.PREPARING, "Preparing...")
	for i in 8:
		await get_tree().process_frame
	assert_false(title.warming(), "its frames are drawn (counted headless)")
	assert_true(title.state().new_game, "New Game is enabled after the warm-up")
	assert_eq(title.state().note, "", "the note is gone")
	assert_true(title.warmup_viewport() != null, "the viewport stays until a game starts")
	title.button("New Game").pressed.emit()
	var c := stack.top() as CreatorScreen
	assert_true(c != null, "the creator")
	c.begin_button.pressed.emit()
	assert_eq(title.warmup_viewport(), null, "a game starting (a level loading) frees the warm-up")
