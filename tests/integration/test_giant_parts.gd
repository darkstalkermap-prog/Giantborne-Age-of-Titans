extends TestSuite
## P48 (plan M11 §2.2, §3.1 design 5-7): the giant's parts on demand, the shadow proxy and the leaf chains,
## as the game loads them. Reads the committed sources and the saved scenes/player/giant_model.tscn:
##   * a hidden part's node is there (GiantLook finds meshes by their nodes) and holds no mesh; showing it
##     loads the part on the model's skeleton, hiding it lets it go; the body is never let go;
##   * ensure_part / release_unused / loaded_parts; an unknown id is null;
##   * two models showing the same part hold the same Mesh (one load); the recent list keeps the last
##     PART_KEEP parts let go, so a style turned off and on again is not read twice;
##   * every part binds to the model's one Skin (its glTF's skin equals it bind for bind) and is weighted
##     to bones of the model's skeleton only: cards to head and their chains, the cape to its chains;
##   * the shadow proxy: shadows only, the other meshes cast none, the free cape keeps its own;
##   * the saved scene keeps none of it (the part nodes are made at run time), reloaded from disk;
##   * GiantLook draws a look through the part nodes without knowing about parts.

const MODEL := "res://scenes/player/giant_model.tscn"
const BODY := ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes"]
const WEIGHT_CHECKED := ["Hair_long_braided", "Hair_crop", "Beard_forked", "Garment_cape", "Garment_tunic_core", "Garment_boots"]


func _model() -> GiantModel:
	var m := (load(MODEL) as PackedScene).instantiate() as GiantModel
	add_child(m)
	return m


func _part_ids(m: GiantModel) -> Array:
	var out: Array = []
	for id: String in m.index.meshes:
		if m.is_part(id):
			out.append(id)
	out.sort()
	return out


func test_parts_load_when_shown_and_are_let_go_when_hidden() -> void:
	var m := _model()
	var parts := _part_ids(m)
	assert_eq(parts.size(), 90, "eighteen hair and beard meshes (P56: nine more), 41 garment meshes (P54: 28 more; P61: the hide mantle and the war harness; B1: the nasal helm), 8 accessories, 3 bead sets (P56; P61: the iron rings), (B1) the Quarry set's 4 modelled pieces and (B2) the Iron, Hide and Kingsfall sets' 10 and (B3) the Warden set's 3 are parts")
	var shown: Array = m.index.defaults.shown
	for id: String in parts:
		var mi := m.mesh(id)
		assert_true(mi != null and mi.get_parent() == m.skeleton(), "%s has its node under the skeleton" % id)
		if mi == null:
			continue
		assert_eq(mi.mesh != null, shown.has(id), "%s: loaded only when the default look shows it" % id)
		assert_eq(m.is_part_loaded(id), shown.has(id), "is_part_loaded(%s)" % id)
	for id: String in BODY:
		assert_true(not m.is_part(id) and m.mesh(id).mesh != null, "%s is in giant.glb itself" % id)
	var hidden := "Hair_wild_mane"
	var mi := m.mesh(hidden)
	mi.visible = true
	assert_true(mi.mesh != null and mi.skin != null, "showing a part's node loads it")
	assert_eq(mi.mesh.get_surface_count(), 1, "one surface")
	assert_eq(int(mi.mesh.surface_get_array_index_len(0)) / 3, int(m.index.meshes[hidden].tris), "its triangles")
	assert_true(m.loaded_parts().has(hidden), "loaded_parts() lists it")
	mi.visible = false
	assert_true(mi.mesh == null, "hiding it lets its mesh go")
	assert_true(mi.skin != null, "its node keeps the model's skin")
	# the body stays whatever is asked
	m.release_unused([])
	assert_eq(m.loaded_parts().size(), 0, "release_unused([]) lets every part go")
	for id: String in BODY:
		assert_true(m.mesh(id).mesh != null, "%s is never let go" % id)
	assert_true(m.shadow_proxy() != null and m.shadow_proxy().mesh != null, "nor the shadow proxy")
	assert_true(m.ensure_part("Beard_forked") == m.mesh("Beard_forked") and m.is_part_loaded("Beard_forked"),
		"ensure_part loads a part whether or not it is shown")
	assert_true(m.ensure_part("Body_Head") == m.mesh("Body_Head"), "ensure_part of a body mesh is that mesh")
	assert_true(m.ensure_part("Hair_nothing") == null, "an unknown id is null")
	m.release_unused(["Beard_forked", "Hair_long_back"])
	assert_eq(Array(m.loaded_parts()), ["Beard_forked"], "release_unused keeps what the look shows")
	m.free()


func test_two_models_share_a_part_and_the_recent_list_spares_a_reload() -> void:
	GiantModel.clear_recent_parts()
	var a := _model()
	var b := _model()
	var id := "Hair_long_back"
	assert_true(a.mesh(id).mesh != null and a.mesh(id).mesh == b.mesh(id).mesh, "two giants with the same hair hold one Mesh")
	var before := int(GiantModel.part_stats().loads)
	a.mesh("Garment_jerkin").visible = true
	assert_eq(int(GiantModel.part_stats().loads), before + 1, "a part not seen before is read once")
	b.mesh("Garment_jerkin").visible = true
	assert_eq(int(GiantModel.part_stats().loads), before + 1, "the second model takes the loaded one")
	assert_true(a.mesh("Garment_jerkin").mesh == b.mesh("Garment_jerkin").mesh, "the same Mesh")
	a.mesh("Garment_jerkin").visible = false
	b.mesh("Garment_jerkin").visible = false
	assert_true(Array(GiantModel.part_stats().recent).has("res://assets/giant/parts/Garment_jerkin.glb"),
		"the part let go last stays in the recent list")
	a.mesh("Garment_jerkin").visible = true
	assert_eq(int(GiantModel.part_stats().loads), before + 1, "turned on again: not read again")
	a.mesh("Garment_jerkin").visible = false
	# more parts than the list keeps: the oldest is dropped
	for other: String in ["Hair_crop", "Hair_wild_mane", "Beard_short", "Beard_forked", "Hair_warrior_tail", "Garment_furs"]:
		a.mesh(other).visible = true
		a.mesh(other).visible = false
	var recent: Array = Array(GiantModel.part_stats().recent)
	assert_true(recent.size() <= GiantModel.PART_KEEP and recent.size() >= 3, "the recent list holds a few parts (%d)" % recent.size())
	assert_false(recent.has("res://assets/giant/parts/Garment_jerkin.glb"), "the oldest left it")
	assert_true(recent.has("res://assets/giant/parts/Garment_furs.glb"), "the newest is in it")
	a.free()
	b.free()


## Plan M11 §2.12: the giant's resident meshes at most 4.5 MB in play (M10 kept every style loaded: 5.98 MB).
func test_the_fullest_look_keeps_the_mesh_buffers_under_the_budget() -> void:
	var m := _model()
	var idx: Dictionary = m.index
	var every := 0
	var costs := {}
	for id: String in _part_ids(m):
		var mesh := m.ensure_part(id).mesh
		costs[id] = GiantModel.part_cost(mesh)
		every += int(costs[id])
		if id in ["Hair_wild_mane", "Garment_tunic_core", "Beard_short"]:
			var exact := GiantModel.mesh_bytes(mesh)      # read back from the renderer: slow, three are enough
			assert_true(absf(float(costs[id]) / float(exact) - 1.0) < 0.25, "%s: part_cost (%d) is near its buffers (%d)" % [id, int(costs[id]), exact])
	m.release_unused([])
	GiantModel.clear_recent_parts()
	var core := m.resident_bytes()
	assert_true(core > 900000 and core < 1500000, "the body, the eyes and the proxy: %d bytes" % core)
	var default_bytes := core
	for id: String in idx.defaults.shown:
		default_bytes += int(costs.get(id, 0))
	var full: Array = ["Hair_wild_mane", "Beard_full"]
	for g: String in ["tunic", "jerkin", "belt", "bracers", "boots"]:
		full.append_array(idx.garments[g])
	for id: String in full:
		m.mesh(id).visible = true
	assert_eq(m.loaded_parts().size(), full.size(), "the fullest look's parts are the loaded ones")
	var fullest := core
	for id: String in full:
		fullest += int(costs[id])
	# the worst the recent list can add: turn the largest other parts on and off
	var others: Array = _part_ids(m).filter(func(id: String) -> bool: return not full.has(id))
	others.sort_custom(func(a: String, b: String) -> bool: return int(costs[a]) < int(costs[b]))     # the largest last
	for id: String in others:
		m.mesh(id).visible = true
		m.mesh(id).visible = false
	var resident := fullest + GiantModel.recent_bytes()
	assert_true(GiantModel.recent_bytes() <= int(GiantModel.PART_KEEP_BYTES * 1.25), "the recent list is capped (%d bytes)" % GiantModel.recent_bytes())
	assert_true(resident <= 4500000 * 0.85, "the fullest look and the recent list: %d bytes of mesh buffers, under 4.5 MB less the renderer's overhead" % resident)
	# P51: the crop and the short beard ship as their skin (the game stacks the shells at load time), so every part
	# together is about 0.5 MB less than at W29 and the margin is smaller
	assert_true(core + every > resident + 300000, "less than every part resident (%d against %d)" % [core + every, resident])
	print("    test_giant_parts: mesh buffers %.2f MB the body, %.2f the default look, %.2f the fullest, %.2f with the recent list at its worst, %.2f with every part (M10)" % [
		core / 1048576.0, default_bytes / 1048576.0, fullest / 1048576.0, resident / 1048576.0, (core + every) / 1048576.0])
	m.free()


func test_every_part_binds_to_the_models_skin_and_bones() -> void:
	var m := _model()
	var sk := m.skeleton()
	var skin := m.mesh("Body_Head").skin
	assert_eq(skin.get_bind_count(), sk.get_bone_count(), "the model's skin binds its 71 bones")
	var chains: Dictionary = m.index.chains
	for id: String in _part_ids(m):
		var mi := m.ensure_part(id)
		assert_true(mi != null and mi.mesh != null, "%s loads" % id)
		if mi == null or mi.mesh == null:
			continue
		assert_true(mi.skin == skin, "%s is bound by the model's own skin" % id)
		assert_true(mi.get_node_or_null(mi.skeleton) == sk, "%s: its skeleton path is the model's skeleton" % id)
		var part_skin: Skin = GiantModel.load_part(str(m.index.meshes[id][GiantModel.PART_PATH])).skin
		assert_true(GiantModel.same_binds(skin, part_skin), "%s: its glTF's skin equals the model's, bind for bind" % id)
		# the bones its vertices are weighted to (read back from the mesh: slow, so a part of each kind; the
		# pipeline's own tests read every part's glTF)
		if not id in WEIGHT_CHECKED:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var used := {}
		for i in bones.size():
			if weights[i] > 0.0:
				used[str(skin.get_bind_name(bones[i]))] = true
		var e: Dictionary = m.index.meshes[id]
		var cat := str(e.category)
		var own := {}
		for c: String in e.get("chains", []):
			for bone: String in chains[c].bones:
				own[bone] = true
		for bone: String in used:
			assert_true(sk.find_bone(bone) >= 0, "%s: %s is a bone of the skeleton" % [id, bone])
			if cat in ["hair", "beard"]:
				assert_true(bone == "head" or own.has(bone), "%s: a card hangs on head and its chains (%s)" % [id, bone])
			elif not bool(e.get("free", false)):
				assert_false(bone.begins_with("hair") or bone.begins_with("beard") or bone.begins_with("cape"),
					"%s: a garment on the skin is on no leaf bone (%s)" % [id, bone])
		for c: String in e.get("chains", []):
			var some := false
			for bone: String in chains[c].bones:
				some = some or used.has(bone)
			assert_true(some, "%s is weighted to its chain %s" % [id, c])
		assert_true((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"%s carries the build channels (COLOR)" % id)
	m.free()


func test_the_shadow_proxy_casts_the_giants_shadow() -> void:
	var m := _model()
	var proxy := m.shadow_proxy()
	assert_true(proxy != null and proxy.mesh != null and proxy.skin != null, "the shadow proxy is a skinned mesh of giant.glb")
	if proxy == null:
		m.free()
		return
	assert_eq(proxy.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "drawn in shadow passes only")
	assert_true(proxy.visible, "and shown")
	assert_eq(proxy.layers, 1 << (GiantModel.SHADOW_PROXY_LAYER - 1), "on its layer")
	# Gate A: the renderer culls a shadow caster by the camera's mask too; on the head's layer (W29) first person and
	# the pressed third-person camera lost the giant's shadow
	for mask: int in [CameraRig.CULL_ALL, CameraRig.CULL_NO_HEAD, CameraRig.CULL_FIRST_PERSON, GiantPreview.FP_CULL]:
		assert_true((proxy.layers & mask) != 0, "every camera keeps the proxy's layer (mask %x), so its shadow is cast" % mask)
	var tris := int(proxy.mesh.surface_get_array_index_len(0)) / 3
	assert_eq(tris, int(m.index.shadow_proxy.tris), "the index counts its triangles")
	assert_true(tris >= 2300 and tris <= 2700, "about 2,500 triangles (%d)" % tris)
	assert_false(m.index.meshes.has("ShadowProxy"), "no look lists it")
	for id: String in m.index.meshes:
		var want := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(m.index.meshes[id].get("free", false)) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		assert_eq(m.mesh(id).cast_shadow, want, "%s: %s" % [id, "a free mesh keeps its own shadow" if want != 0 else "casts through the proxy"])
	assert_true(bool(m.index.meshes["Garment_cape"].get("free", false)), "the cape is the free mesh")
	# the proxy follows the body: inside its box, weighted to the body's bones
	var body := m.mesh("Body_Limbs").get_aabb().merge(m.mesh("Body_Head").get_aabb()).merge(m.mesh("Body_Torso").get_aabb())
	assert_true(body.grow(0.02).encloses(proxy.get_aabb()), "the proxy lies within the body's box")
	assert_true(proxy.get_aabb().size.y > 0.95 * body.size.y, "and is as tall")
	m.free()


func test_the_saved_scene_keeps_no_part_node_and_giantlook_draws_through_them() -> void:
	var text := FileAccess.get_file_as_string(MODEL)
	assert_false(text.contains("Hair_long_back") and text.contains("type=\"MeshInstance3D\""),
		"giant_model.tscn saves no part node (they are made at run time)")
	var packed := ResourceLoader.load(MODEL, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var m := packed.instantiate() as GiantModel
	# outside the tree: the part nodes are there as soon as the scene is instanced
	assert_true(m.mesh("Hair_crop") != null and m.mesh("Garment_cape") != null, "the part nodes exist before _ready")
	assert_eq(GiantLook.validate(m, m.index, GiantLook.DEFAULT_LOOK), PackedStringArray(), "GiantLook finds every index mesh's node")
	add_child(m)
	var look := GiantLook.DEFAULT_LOOK.duplicate(true)
	look.hair_mesh = "Hair_warrior_tail"
	look.beard_mesh = "Beard_braided"
	look.garments = ["tunic", "belt", "cape"]
	GiantLook.apply(m, m.index, look)
	var want := ["Beard_braided", "Garment_belt", "Garment_cape", "Garment_tunic_core", "Garment_tunic_limbs", "Hair_warrior_tail"]
	assert_eq(Array(m.loaded_parts()), want, "a look's parts are the loaded ones, the others are let go")
	for id: String in want:
		assert_true(m.mesh(id).visible and m.mesh(id).mesh != null, "%s is shown with its mesh" % id)
	GiantLook.apply(m, m.index, GiantLook.DEFAULT_LOOK)
	assert_eq(Array(m.loaded_parts()), ["Beard_full", "Garment_belt", "Garment_braies_core", "Garment_braies_limbs", "Hair_long_back"],
		"back to the default look's five parts")
	# a copy of a model (Node.duplicate) has one node a part, not the original's run-time nodes beside its own
	var copy := m.duplicate() as GiantModel
	add_child(copy)
	var mesh_nodes := 0
	for c in copy.skeleton().get_children():
		if c is MeshInstance3D:
			mesh_nodes += 1
	assert_eq(mesh_nodes, m.index.meshes.size() + 1, "a copied model holds one node a mesh and the proxy")
	assert_eq(Array(copy.loaded_parts()), Array(m.loaded_parts()), "and shows the default look's parts once")
	copy.free()
	m.free()
