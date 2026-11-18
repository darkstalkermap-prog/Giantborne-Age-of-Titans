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
