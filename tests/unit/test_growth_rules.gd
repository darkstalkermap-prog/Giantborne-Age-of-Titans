extends TestSuite
## Growth and shrine rules without a scene (plan §3.5): the shipped stage profiles (§4.8) and
## shrine records, their schemas, the growth gates, scaling and summary helpers of
## PlayerGrowth, the camera's zoom, orbit and head-hiding rules, the rig's arc tilt and dodge
## poses, the per-action arc offsets, and the crosshair probe's ray / bounds test.


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


func _errors(rec: Dictionary) -> String:
	return "\n".join(DataValidator.validate_record(rec, "test.json").errors)


func _growth_record(extra: Dictionary) -> Dictionary:
	var rec := _profile(2).duplicate(true)
	rec["id"] = "growth.test"
	rec.merge(extra, true)
	return rec


func _shrine_record(extra: Dictionary) -> Dictionary:
	var rec := {"schema_version": 1, "id": "shrine.test", "type": "shrine", "allows_growth": true, "max_stage": 2}
	rec.merge(extra, true)
	return rec


# --------------------------------------------------------------------------- shipped data

func test_stage_profiles_carry_the_section_4_8_values() -> void:
	var expect := {
		1: {"weapon_scale": 1.0, "grab_lunge_m": 2.0, "grab_capacity": "small", "attach": ["torso_fist", "scruff"],
			"bonus": {}, "dodge": "roll", "orbit": 1.0, "nav": 8, "shake": 0.0},
		2: {"weapon_scale": 1.5, "grab_lunge_m": 2.7, "grab_capacity": "small", "attach": ["torso_fist", "scruff"],
			"bonus": {"health": 150.0, "stamina": 10.0}, "dodge": "sidestep", "orbit": 1.5, "nav": 4, "shake": 0.05},
		3: {"weapon_scale": 2.1667, "grab_lunge_m": 3.5, "grab_capacity": "medium",
			"attach": ["torso_fist", "scruff", "two_hand"], "bonus": {"health": 300.0, "stamina": 20.0},
			"dodge": "sidestep", "orbit": 2.17, "nav": 4, "shake": 0.12},
	}
	for stage: int in expect:
		var p := _profile(stage)
		var e: Dictionary = expect[stage]
		assert_false(p.is_empty(), "stage %d has a profile" % stage)
		assert_near(float(p.weapon_scale), float(e.weapon_scale), 1e-6, "stage %d weapon_scale" % stage)
		assert_near(float(p.weapon_scale), PlayerGrowth.body_scale_for(p), 1e-3, "stage %d weapon_scale = height ratio" % stage)
		assert_near(float(p.grab_reach_m), float(p.melee_reach_m) + 0.5, 1e-6, "stage %d grab reach = melee reach + 0.5" % stage)
		assert_near(float(p.grab_lunge_m), float(e.grab_lunge_m), 1e-6, "stage %d grab lunge" % stage)
		assert_eq(p.grab_capacity, e.grab_capacity, "stage %d grab capacity" % stage)
		assert_eq(p.grab_attach, e.attach, "stage %d attachment profiles" % stage)
		assert_eq(PlayerGrowth.resource_bonus(p), e.bonus, "stage %d resource bonus" % stage)
		assert_eq(p.dodge_style, e.dodge, "stage %d dodge style" % stage)
		assert_near(float(p.camera_orbit_scale), float(e.orbit), 1e-6, "stage %d camera orbit scale" % stage)
		assert_eq(int(p.nav_layers), int(e.nav), "stage %d nav layers" % stage)
		assert_near(float(p.footstep_shake), float(e.shake), 1e-6, "stage %d footstep shake" % stage)
		for id: Variant in p.get("unlocks", []):
			assert_true(GameData.get_action(str(id)) != null, "stage %d unlock %s is an action" % [stage, id])
	assert_near(float(_profile(1).lock_range_m), 35.0, 1e-6, "lock range 35")
	assert_near(float(_profile(2).lock_range_m), 40.0, 1e-6, "40")
	assert_near(float(_profile(3).lock_range_m), 45.0, 1e-6, "45")


## Decision 5: the arcs tilt down at the bigger stages, never deeper than the plan allows
## (stage 2 down to -10, stage 3 down to -18). The final values and why are in
## docs/systems/P05.md.
func test_arc_pitch_offsets_stay_within_the_plan() -> void:
	assert_near(PlayerAttack.offset_for(_profile(1), "ability.light_1"), 0.0, 1e-9, "stage 1: no tilt")
	for id in ["ability.light_1", "ability.light_2", "ability.light_3", "ability.heavy_1"]:
		var o2 := PlayerAttack.offset_for(_profile(2), id)
		var o3 := PlayerAttack.offset_for(_profile(3), id)
		assert_true(o2 < 0.0 and o2 >= -10.0, "stage 2 %s tilt %.0f in [-10, 0)" % [id, o2])
		assert_true(o3 < 0.0 and o3 >= -18.0, "stage 3 %s tilt %.0f in [-18, 0)" % [id, o3])
		assert_true(o3 <= o2, "stage 3 tilts at least as far as stage 2 (%s)" % id)
	assert_near(PlayerAttack.offset_for(_profile(2), "ability.light_2"), -8.0, 1e-9, "stage 2 base -8")
	assert_near(PlayerAttack.offset_for(_profile(3), "ability.light_3"), -12.0, 1e-9, "stage 3 base -12")
	assert_near(PlayerAttack.offset_for(_profile(3), "ability.light_1"), -16.0, 1e-9, "stage 3 light 1 -16")
	assert_near(PlayerAttack.offset_for({}, "ability.light_1"), 0.0, 1e-9, "no profile: no tilt")
	assert_near(PlayerAttack.offset_for({"arc_pitch_offset_deg": -5, "arc_pitch_offsets_deg": {"a.b": -9}}, "a.c"),
		-5.0, 1e-9, "an action without an entry uses the base tilt")


func test_shipped_shrines() -> void:
	var grove := GameData.get_record("shrine.grove")
	assert_true(bool(grove.allows_growth) and int(grove.max_stage) == 2, "the Grove grows to stage 2")
	assert_eq((grove.get("growth_requires_flags", []) as Array).size(), 0, "with no flags (level 3 comes from growth.02)")
	var kings := GameData.get_record("shrine.kingsfall")
	assert_true(bool(kings.allows_growth) and int(kings.max_stage) == 3, "Kingsfall grows to stage 3")
	assert_eq(kings.growth_requires_flags, ["world.ogre_king.defeated"], "after the boss (decision 12)")
	assert_true(str(kings.get("growth_locked_message", "")) != "", "and says why it will not")
	for id in ["shrine.hollow", "shrine.thornwick"]:
		assert_false(bool(GameData.get_record(id).allows_growth), "%s does not grow" % id)
	var sandbox := GameData.get_record("shrine.sandbox")
	assert_true(bool(sandbox.allows_growth) and int(sandbox.max_stage) == 3, "the sandbox shrine grows to stage 3")
	assert_eq((sandbox.get("growth_requires_flags", []) as Array).size(), 0, "with no flags")
	for id in ["shrine.hollow", "shrine.grove", "shrine.thornwick", "shrine.kingsfall", "shrine.sandbox"]:
		var rec := GameData.get_record(id)
		assert_near(float(rec.get("activation_radius_m", 0.0)), 14.0, 1e-6, "%s activates within 14 m" % id)
		for key in ["checkpoint", "rest_heals", "first_activation_rest", "loadout", "attributes"]:
			assert_true(bool(rec.get(key, false)), "%s %s" % [id, key])
	assert_eq(GameData.REQUIRED_RECORDS.get("shrine.sandbox", ""), "shrine", "the sandbox shrine is a required record")


# --------------------------------------------------------------------------- schemas

func test_growth_profile_schema_fields() -> void:
	assert_eq(_errors(_growth_record({})), "", "the stage-2 record validates")
	assert_true(_errors(_growth_record({"grab_capacity": "huge"})).contains("unknown value 'huge'"), "grab_capacity enum")
	assert_true(_errors(_growth_record({"grab_attach": ["teeth"]})).contains("unknown value 'teeth'"), "grab_attach enum")
	assert_true(_errors(_growth_record({"arc_pitch_offset_deg": 5})).contains("must be <= 0"), "arcs never tilt up")
	assert_true(_errors(_growth_record({"arc_pitch_offset_deg": -31})).contains("must be >= -30"), "at most 30 degrees down")
	assert_true(_errors(_growth_record({"arc_pitch_offsets_deg": {"ability.light_1": 3}})).contains("must be <= 0"),
		"per-action tilts are range-checked too")
	assert_true(_errors(_growth_record({"nav_layers": 0})).contains("must be >= 1"), "nav layers 1-255")
	assert_true(_errors(_growth_record({"dodge_style": "flip"})).contains("unknown value 'flip'"), "dodge style enum")
	assert_true(_errors(_growth_record({"resource_bonus": {"fury": 5}})).contains("unknown key 'fury'"), "bonus keys")
	assert_true(_errors(_growth_record({"resource_bonus": {"health": -5}})).contains("must be >= 0"), "bonus values")
	assert_true(_errors(_growth_record({"footstep_shake": 2})).contains("must be <= 1"), "shake 0-1")
	assert_true(_errors(_growth_record({"weapon_scale": 0})).contains("must be > 0"), "weapon scale > 0")
	var out := DataValidator.validate_record(_growth_record({"arc_pitch_offsets_deg": {"ability.nope": -5}}), "test.json")
	var refs := DataValidator.validate_references(GameData.records, out.refs)
	assert_true("\n".join(refs).contains("missing reference 'ability.nope'"), "per-action keys must be actions")


func test_player_schema_fields() -> void:
	var rec := GameData.get_record("player.giant").duplicate(true)
	rec["mass_class"] = "large"
	rec["status_immunities"] = ["Fear"]
	assert_eq(_errors(rec), "", "mass_class and status_immunities validate")
	rec["mass_class"] = "huge"
	assert_true(_errors(rec).contains("unknown value 'huge'"), "mass class enum")
	rec["mass_class"] = "large"
	rec["status_immunities"] = ["Sleepy"]
	assert_true(_errors(rec).contains("unknown value 'Sleepy'"), "status tag enum")


func test_shrine_schema() -> void:
	assert_eq(_errors(_shrine_record({})), "", "a minimal shrine validates")
	for id in ["shrine.hollow", "shrine.grove", "shrine.thornwick", "shrine.kingsfall", "shrine.sandbox"]:
		assert_eq(_errors(GameData.get_record(id)), "", "%s validates" % id)
	var no_max := _shrine_record({})
	no_max.erase("max_stage")
	assert_true(_errors(no_max).contains("missing required key 'max_stage'"), "max_stage is required")
	assert_true(_errors(_shrine_record({"max_stage": 11})).contains("must be <= 10"), "max_stage 1-10")
	assert_true(_errors(_shrine_record({"growth_requires_flags": ["Bad Flag"]})).contains("flag id 'Bad Flag'"),
		"flag ids are checked")
	assert_true(_errors(_shrine_record({"glows": true})).contains("unknown key 'glows'"), "unknown keys")
	assert_true(_errors(_shrine_record({"activation_radius_m": 0})).contains("must be > 0"), "radius > 0")
	var warn := DataValidator.validate_record(_shrine_record({"allows_growth": false,
		"growth_requires_flags": ["world.x.y"]}), "test.json")
	assert_true("\n".join(warn.warnings).contains("no effect"), "flags on a shrine that cannot grow warn")


# --------------------------------------------------------------------------- PlayerGrowth helpers

func test_shrine_and_level_gates() -> void:
	var flags := {"world.ogre_king.defeated": true}
	var get_flag := func(id: String, default: Variant) -> Variant: return flags.get(id, default)
	var none := func(_id: String, default: Variant) -> Variant: return default
	assert_eq(PlayerGrowth.shrine_gate(2, {}, none).reason, "shrine_max", "no shrine, no growth")
	assert_eq(PlayerGrowth.shrine_gate(2, {"allows_growth": false, "max_stage": 3}, none).reason, "shrine_max",
		"a shrine that does not grow")
	assert_eq(PlayerGrowth.shrine_gate(3, {"allows_growth": true, "max_stage": 2}, none).message,
		"This shrine can only make you grow to stage 2.", "beyond its max stage")
	var kings := GameData.get_record("shrine.kingsfall")
	var locked := PlayerGrowth.shrine_gate(3, kings, none)
	assert_eq(locked.reason, "flags", "a missing flag")
	assert_eq(locked.message, str(kings.growth_locked_message), "uses the record's message")
	assert_true(PlayerGrowth.shrine_gate(3, kings, get_flag).ok, "the flag set: open")
	assert_eq(PlayerGrowth.shrine_gate(2, {"allows_growth": true, "max_stage": 2, "growth_requires_flags": ["a.b"]},
		none).message, "Something still binds this shrine's power.", "the default flags message")
	assert_true(PlayerGrowth.level_gate(_profile(2), 3).ok, "level 3 grows to stage 2")
	assert_eq(PlayerGrowth.level_gate(_profile(2), 2).reason, "level", "level 2 does not")
	assert_eq(PlayerGrowth.level_gate(_profile(3), 4).message, "You must reach level 5 to grow to stage 3.", "names it")
	assert_true(PlayerGrowth.level_gate(_profile(3), 99).ok, "99 = no level gating (sandbox, tests)")


func test_reasons_messages_and_result_shapes() -> void:
	var seen := {}
	for reason: String in PlayerGrowth.REASONS:
		var r := PlayerGrowth.result_fail(reason)
		assert_eq(r.keys(), ["ok", "reason", "message"], "%s result keys" % reason)
		assert_false(r.ok, "%s fails" % reason)
		assert_true(str(r.message) != "", "%s has a player-facing message" % reason)
		seen[r.message] = true
	assert_eq(seen.size(), PlayerGrowth.REASONS.size(), "every reason reads differently")
	assert_eq(PlayerGrowth.default_message("clearance"), "Not enough room to grow here. Step into the open.", "clearance")
	assert_eq(PlayerGrowth.default_message("combat"), "Enemies are near. You cannot grow while fighting.", "combat")
	assert_eq(PlayerGrowth.result_fail("level", "custom").message, "custom", "a custom message wins")
	assert_eq(PlayerGrowth.result_ok(), {"ok": true, "reason": "", "message": ""}, "ok")


func test_slots_bonus_scale_and_profiles() -> void:
	var lo := {"slot_1": "a.b", "slot_2": "", "slot_3": "c.d"}
	assert_eq(PlayerGrowth.first_empty_slot(lo), "slot_2", "the first empty slot")
	var full := {}
	for i in 8:
		full["slot_%d" % (i + 1)] = "x.y"
	assert_eq(PlayerGrowth.first_empty_slot(full), "", "none when all are full")
	assert_eq(PlayerGrowth.first_empty_slot({}), "slot_1", "missing keys are empty")
	assert_eq(PlayerGrowth.resource_bonus({}), {}, "no bonus")
	assert_eq(PlayerGrowth.resource_bonus({"resource_bonus": {"health": 1, "essence": 2}}), {"health": 1.0, "essence": 2.0},
		"floats; only the pools")
	assert_near(PlayerGrowth.body_scale_for(_profile(1)), 1.0, 1e-9, "k = 1 at stage 1")
	assert_near(PlayerGrowth.body_scale_for(_profile(2)), 1.5, 1e-9, "k = 1.5 at stage 2")
	assert_near(PlayerGrowth.body_scale_for(_profile(3)), 2.1667, 1e-4, "k = 2.1667 at stage 3")
	assert_true(PlayerGrowth.find_profile([], 2).is_empty(), "no records: no profile")
	assert_eq(PlayerGrowth.find_profile([{"stage": 1, "id": "a"}, {"stage": 2, "id": "b"}], 2).id, "b", "by stage")


func test_scaled_shapes_are_copies() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 3)
	var b := PlayerGrowth.scaled_shape(box, 2.0) as BoxShape3D
	assert_true(b.size.is_equal_approx(Vector3(2, 4, 6)), "box size x k")
	assert_true(box.size.is_equal_approx(Vector3(1, 2, 3)), "the source is untouched")
	assert_true(b != box, "a new resource")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	assert_near((PlayerGrowth.scaled_shape(sphere, 1.5) as SphereShape3D).radius, 0.75, 1e-6, "sphere radius x k")
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 2.0
	var c := PlayerGrowth.scaled_shape(cap, 3.0) as CapsuleShape3D
	assert_true(is_equal_approx(c.radius, 1.5) and is_equal_approx(c.height, 6.0), "capsule x k")
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = 1.0
	var y := PlayerGrowth.scaled_shape(cyl, 2.0) as CylinderShape3D
	assert_true(is_equal_approx(y.radius, 0.5) and is_equal_approx(y.height, 2.0), "cylinder x k")


func test_change_summary() -> void:
	var s := PlayerGrowth.change_summary(_profile(2), _profile(3), {"health": 650.0, "stamina": 110.0, "essence": 100.0},
		{"health": 800.0, "stamina": 120.0, "essence": 100.0}, [], {"display_name": "Oak Club", "fit_max_stage": 2})
	assert_eq(s.stage, [2, 3], "stages")
	assert_eq(s.permissions, ["tree_weapon"], "stage 3 adds uprooting trees")
	assert_true(bool(s.weapon_too_small), "a club that fits stage 2 is too small at stage 3")
	var text := "\n".join(s.lines)
	assert_true(text.contains("Height 5.5 m -> 7.9 m"), "height line (%s)" % text)
	assert_true(text.contains("Reach 4.8 m -> 6.5 m"), "reach line")
	assert_true(text.contains("Health 650 -> 800"), "health line")
	assert_true(text.contains("Uproot ancient oaks"), "the new interaction")
	assert_true(text.contains("Your Oak Club is too small for you now."), "the weapon warning")
	var fits := PlayerGrowth.change_summary(_profile(1), _profile(2), {}, {}, [{"id": "ability.runic_bolt", "slot": "slot_6"}],
		{"display_name": "Oak Club"})
	assert_false(bool(fits.weapon_too_small), "no fit_max_stage: never too small")
	assert_true("\n".join(fits.lines).contains("Learned Runic Bolt (slot 6)"), "learned abilities are listed")


# --------------------------------------------------------------------------- camera and rig

func test_zoom_fraction_between_stages() -> void:
	var g1 := _profile(1)
	var g2 := _profile(2)
	var g3 := _profile(3)
	var frac := (6.5 - 4.5) / (9.0 - 4.5)
	assert_near(CameraRig.zoomed_distance(g1, g2, 6.5), lerpf(6.5, 12.0, frac), 1e-6, "stage 1 -> 2 keeps the fraction")
	assert_near(CameraRig.zoomed_distance(g2, g3, 12.0), 16.0, 1e-6, "zoomed all the way out stays all the way out")
	assert_near(CameraRig.zoomed_distance(g3, g1, 9.0), 4.5, 1e-6, "and all the way in")
	assert_near(CameraRig.zoomed_distance({}, g2, 3.0), 9.0, 1e-6, "no previous profile: the stage's default")
	var flat := {"camera_zoom_min_m": 5.0, "camera_zoom_max_m": 5.0, "camera_distance_m": 5.0}
	assert_near(CameraRig.zoomed_distance(flat, g2, 5.0), 9.0, 1e-6, "a degenerate range uses the default")


func test_head_hiding_rule() -> void:
	for stage in [1, 2, 3]:
		var p := _profile(stage)
		var r := float(p.capsule_radius_m)
		var s := float(p.camera_shoulder_offset_m)
		var full := Vector2(s, float(p.camera_distance_m)).length()
		assert_false(CameraRig.hides_head(full, full, s, r), "stage %d: a free arm shows the head" % stage)
		assert_true(CameraRig.hides_head(1.19 * r, full, s, r), "stage %d: an arm under 1.2 x radius hides it" % stage)
	var g3 := _profile(3)
	var full3 := Vector2(1.6, 12.11).length()
	assert_true(CameraRig.hides_head(3.26, full3, 1.6, float(g3.capsule_radius_m)),
		"stage 3 under the growth course's 8.6 m ceiling (arm 3.26 m): the centre ray would pass through the head")
	assert_false(CameraRig.hides_head(6.4, full3, 1.6, float(g3.capsule_radius_m)),
		"past the 5 m doorway (arm 6.4 m) the ray clears the head")
	assert_false(CameraRig.hides_head(2.0, 0.0, 1.0, 0.85), "no arm length: only the radius rule applies")


func test_lock_orbit_scales_with_the_stage() -> void:
	assert_near(CameraRig.lock_orbit_rad(20.0, 1.0), 0.0, 1e-9, "no orbit far away")
	assert_near(CameraRig.lock_orbit_rad(3.0, 1.0), deg_to_rad(CameraRig.LOCK_ORBIT_DEG), 1e-9, "full orbit close in")
	assert_near(CameraRig.lock_orbit_rad(12.0, 1.0), 0.0, 1e-9, "the ramp starts at 12 m")
	assert_near(CameraRig.lock_orbit_rad(6.5, 2.17), deg_to_rad(CameraRig.LOCK_ORBIT_DEG), 1e-6,
		"stage 3 (x 2.17): full orbit already at 6.5 m")
	assert_true(CameraRig.lock_orbit_rad(20.0, 2.17) > 0.0, "and still orbiting at 20 m")


func test_rig_arc_tilt_weight_and_dodge_poses() -> void:
	assert_near(ActorRig.arc_offset_weight(ActionDef.Phase.WINDUP, 0.0), 0.0, 1e-9, "no tilt at the start of the windup")
	assert_near(ActorRig.arc_offset_weight(ActionDef.Phase.WINDUP, 1.0), 1.0, 1e-9, "full at its end")
	assert_near(ActorRig.arc_offset_weight(ActionDef.Phase.ACTIVE, 0.3), 1.0, 1e-9, "full while active (the swept arc)")
	assert_near(ActorRig.arc_offset_weight(ActionDef.Phase.RECOVERY, 0.0), 1.0, 1e-9, "full when the recovery starts")
	assert_near(ActorRig.arc_offset_weight(ActionDef.Phase.RECOVERY, 1.0), 0.0, 1e-9, "none at its end")
	assert_near(ActorRig.arc_offset_weight(ActionDef.Phase.NONE, 0.5), 0.0, 1e-9, "none outside an action")
	var roll: Array = ActorRig.dodge_lean("roll", Vector3(0, 0, 1))
	var side: Array = ActorRig.dodge_lean("sidestep", Vector3(0, 0, 1))
	assert_true(absf((side[0] as Vector3).x) < absf((roll[0] as Vector3).x), "the sidestep pitches less than the roll")
	assert_true(float(side[1]) < float(roll[1]), "and is reached more slowly")
	var side_lat: Array = ActorRig.dodge_lean("sidestep", Vector3(1, 0, 0))
	assert_true(absf((side_lat[0] as Vector3).z) > absf((side[0] as Vector3).x), "it leans sideways more than it pitches")
	assert_eq(ActorRig.dodge_arm_pose("roll"), [Vector2(25.0, -50.0), Vector2(-25.0, -50.0)], "the M1 roll arms")
	assert_true(ActorRig.dodge_arm_pose("sidestep") != ActorRig.dodge_arm_pose("roll"), "the sidestep arms differ")


# --------------------------------------------------------------------------- crosshair probe

func test_probe_ray_and_bounds() -> void:
	var box := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var at := Transform3D(Basis(), Vector3(0, 0, -10))
	assert_near(CrosshairProbe.ray_aabb_distance(Vector3.ZERO, Vector3.FORWARD, at, box, 40.0), 9.0, 1e-5, "hit 9 m ahead")
	assert_eq(CrosshairProbe.ray_aabb_distance(Vector3.ZERO, Vector3.BACK, at, box, 40.0), INF, "behind the ray: no hit")
	assert_eq(CrosshairProbe.ray_aabb_distance(Vector3(5, 0, 0), Vector3.FORWARD, at, box, 40.0), INF, "beside it: no hit")
	assert_eq(CrosshairProbe.ray_aabb_distance(Vector3.ZERO, Vector3.FORWARD, at, box, 5.0), INF, "beyond the range: no hit")
	assert_near(CrosshairProbe.ray_aabb_distance(Vector3(0, 0, -10), Vector3.FORWARD, at, box, 40.0), 0.0, 1e-9,
		"starting inside: distance 0")
	var scaled := Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3(0, 0, -10))
	assert_near(CrosshairProbe.ray_aabb_distance(Vector3.ZERO, Vector3.FORWARD, scaled, box, 40.0), 8.0, 1e-5,
		"a node scaled x2 is hit 8 m ahead (distances in world space)")
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3(0, 0, -10))
	assert_near(CrosshairProbe.ray_aabb_distance(Vector3.ZERO, Vector3.FORWARD, turned, box, 40.0), 10.0 - sqrt(2.0), 1e-4,
		"a box turned 45 degrees is hit at its corner")
