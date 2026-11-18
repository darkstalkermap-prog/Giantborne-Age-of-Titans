extends IntegrationSuite
## SecondaryMotion (P50; plan M11 §2.3, §3.3 item 4, probe 4): the hair, beard, braids and cape on the engine's
## springs with this package's angle limits.
##   * a chain runs only while a shown mesh hangs on it: the index's chains by mesh, none for the crop, the short
##     beard and no cape; the live rig runs exactly the look's chains, and a look change re-runs them;
##   * a teleport, a growth and a look change reset the springs (probe 4: without it a teleport throws every
##     chain out to 90 degrees);
## The motion half - the chains swing on a sprint and rest within 1.5 s of the stop, and keep their limits
## through a full head turn and a heavy swing - is tests/slow/test_giant_motion_render.gd (the default tier's
## 0.6 s; plan M11 §3.3).

const LONG_LOOK := {"hair": "hair.long_braided", "beard": "beard.braided", "outfit": "outfit.wayfarer"}
const SHORT_LOOK := {"hair": "hair.crop", "beard": "beard.short", "outfit": "outfit.wanderer"}


func _giant(look: Dictionary) -> GiantPlayer:
	SkinnedRig.enable_for_tests()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	_wear(p, look)
	await step_ticks(2)
	return p


static func _wear(p: GiantPlayer, look: Dictionary) -> void:
	var rec := Appearance.preset_record("appearance_preset.young_giant").duplicate(true)
	rec["hair"]["style"] = look.hair
	rec["beard"]["style"] = look.beard
	rec["outfit"]["set"] = look.outfit
	p.appearance.set_record(rec)


static func _rig(p: GiantPlayer) -> SkinnedRig:
	return p.get_node("Visual") as SkinnedRig


func test_chains_run_only_for_the_meshes_that_hang_on_them() -> void:
	var root := (load(GIANT) as PackedScene).instantiate()
	var index: Dictionary = (root.get_node("Visual/Body/Model") as GiantModel).index
	root.free()
	assert_eq(Array(SecondaryMotion.chains_for(index, ["Hair_crop", "Beard_short", "Body_Torso"])), [], "the crop and the short beard need no springs")
	assert_eq(Array(SecondaryMotion.chains_for(index, ["Hair_long_back"])), ["hair"], "the long back hair hangs on the back chain")
	assert_eq(Array(SecondaryMotion.chains_for(index, ["Hair_long_braided", "Beard_braided", "Garment_cape"])),
		["beard", "cape_c", "cape_l", "cape_r", "hair", "hair_l", "hair_r"], "the braids, the beard and the cape")
	var v := SecondaryMotion.chain_values(index, "cape_c")
	assert_eq(v.kind, "cape", "a chain's kind")
	assert_near(float(v.gravity), float(SecondaryMotion.TUNING.cape.gravity), 1e-6, "the tuning over the index's values")
	assert_near(float(v.max_deg), float(index.chains.cape_c.max_deg), 1e-6, "the index's limit")
	var p := await _giant(SHORT_LOOK)
	var sm := _rig(p).secondary()
	assert_true(sm != null and sm.get_parent() == _rig(p).skeleton(), "SecondaryMotion under the skeleton")
	var kids := _rig(p).skeleton().get_children()
	assert_true(kids.find(_rig(p).modifier()) < kids.find(sm.springs) and kids.find(sm.springs) < kids.find(sm),
		"after the brain's modifier: the springs, then the limits")
	assert_eq(Array(sm.chains), [], "a short look runs no chain")
	assert_false(sm.springs.active or sm.active, "and its modifiers rest")
	var resets := sm.resets
	_wear(p, LONG_LOOK)
	await step_ticks(2)
	assert_eq(Array(sm.chains), ["beard", "cape_c", "cape_l", "cape_r", "hair", "hair_l", "hair_r"], "the long look runs its chains")
	assert_eq(sm.springs.get_setting_count(), 7, "one spring setting a chain")
	assert_true(sm.resets > resets, "a look change resets the springs")
	assert_true(sm.frames > 0, "and they run")


func test_teleports_and_growth_reset_the_springs() -> void:
	var p := await _giant(LONG_LOOK)
	var rig := _rig(p)
	var sm := rig.secondary()
	await step_ticks(3)
	var r0 := sm.resets
	var t0 := rig.teleports
	p.global_position += Vector3(40, 0, 0)
	await step_ticks(2)
	assert_eq(rig.teleports, t0 + 1, "a jump of 40 m is a teleport")
	assert_true(sm.resets > r0, "the springs reset on it")
	var r1 := sm.resets
	assert_true(p.growth.debug_set_stage(2).ok, "stage 2")
	await step_ticks(2)
	assert_true(sm.resets > r1, "growth resets them")
	var r2 := sm.resets
	p.facing_yaw = wrapf(p.facing_yaw + PI * 0.75, -PI, PI)
	await step_ticks(2)
	assert_true(sm.resets > r2, "a snap of the facing is a teleport too")
	await step_ticks(30)
	var worst := 0.0
	var angles := sm.joint_angles()
	for b: String in angles:
		worst = maxf(worst, float(angles[b][0]))
	assert_true(worst < 45.0, "after the reset no chain is thrown out (worst %.1f deg)" % worst)


## The W30 merge: P51's hair geometry on P50's chains. The braids are tubes and beads (UV2.x 1 and 2) that only
## the springs move (the hair shader's sway skips them), so every braid's vertices must hang on its chain's
## bones; the shell styles (the crop, the short beard) are cut from the skin and stacked at load time, and hang on
## the head alone, so they need no chain.
static func _chain_share(mi: MeshInstance3D, bones: Dictionary, kind: float) -> Vector2:
	var arrays := mi.mesh.surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var b: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := w.size() / n
	var sk := mi.get_node(mi.skeleton) as Skeleton3D
	var on_chain := 0.0
	var count := 0
	for v in n:
		if kind >= 0.0 and (uv2.is_empty() or absf(uv2[v].x - kind) > 0.25):
			continue
		count += 1
		for k in per:
			var bind := b[v * per + k]
			var name := str(mi.skin.get_bind_name(bind))
			if name.is_empty():
				name = sk.get_bone_name(mi.skin.get_bind_bone(bind))
			if bones.has(name):
				on_chain += w[v * per + k]
	return Vector2(on_chain / maxf(count, 1), count)


static func _bones_of(index: Dictionary, chain_ids: Array) -> Dictionary:
	var out := {}
	for c: String in chain_ids:
		for bn: Variant in (index.chains[c] as Dictionary).bones:
			out[str(bn)] = true
	return out


func test_the_braids_hang_on_their_chains_and_the_shells_on_the_head() -> void:
	var p := await _giant(LONG_LOOK)
	var model := _rig(p).model()
	var index: Dictionary = model.index
	var sides := _bones_of(index, ["hair_l", "hair_r"])
	for kind in [1.0, 2.0]:
		var s := _chain_share(model.mesh("Hair_long_braided"), sides, kind)
		assert_true(s.y > 0, "the braided hair has its %s" % ("tubes" if kind == 1.0 else "beads"))
		assert_true(s.x > 0.4, "the braids' %s hang on the side chains (share %.2f)" % ["tubes" if kind == 1.0 else "beads", s.x])
	var beard := _chain_share(model.mesh("Beard_braided"), _bones_of(index, ["beard"]), 1.0)
	assert_true(beard.y > 0 and beard.x > 0.5, "the braided beard's tube hangs on the beard chain (share %.2f)" % beard.x)
	var all_chains := _bones_of(index, (index.chains as Dictionary).keys())
	var resets := _rig(p).secondary().resets
	_wear(p, SHORT_LOOK)
	await step_ticks(2)
	for id in ["Hair_crop", "Beard_short"]:
		var mi := model.mesh(id)
		assert_true(mi != null and mi.visible and mi.mesh != null and mi.mesh.has_meta(GiantLook.META_SHELL_STACK),
			"%s is drawn as stacked shells" % id)
		if mi != null and mi.mesh != null:
			assert_near(_chain_share(mi, all_chains, -1.0).x, 0.0, 1e-4, "%s hangs on no chain bone" % id)
	assert_eq(Array(_rig(p).secondary().chains), [], "the shell look runs no chain")
	assert_true(_rig(p).secondary().resets > resets, "and the change to it reset the springs")
