extends IntegrationSuite
## P64c (the M13 gate review): the people's strikes and braces keyed on the action (PersonRig.STRIKE_KEYS), skinned
## headless (PersonRig.enable_for_tests):
##   * the pike's thrust: drawn back at the windup's top (the fist behind the hip), thrust level at the target in the
##     active phase (the pike within 25 degrees of the level, pointing ahead), both fists on the shaft;
##   * the shield's bash: the shield forward of the chest in the active phase, its face to the front;
##   * the archer's kick: the right foot up and ahead at the kick, near the ground again after;
##   * the mage's staff: drawn back over the shoulder in two hands at the windup's top;
##   * the pike's brace: the butt near the ground, the pike angled up ahead, both fists on it; the shield's brace: the
##     shield squared before the body.
## The giant is a stand-in (a node of group "player"): this is presentation.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const SHIELDMAN := "res://scenes/enemies/shieldman.tscn"
const ARCHER := "res://scenes/enemies/archer.tscn"
const MAGE := "res://scenes/enemies/mage.tscn"
## Both fists on a shaft: the off fist's centre within this of the weapon's line (m).
const GRIP_M := 0.07

var player: Node3D


func before_each() -> void:
	await super()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, -6)
	world.add_child(player)
	player.add_to_group("player")


func _spawn(scene: String, id: String) -> EnemyActor:
	var e := (load(scene) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = false
	e.position = Vector3(0, 0.05, 0)
	world.add_child(e)
	return e


## Runs `action` on `e` until its `phase` reaches `at` (fraction), the rig posed; false when it never did.
func _run_to(e: EnemyActor, action: String, phase: int, at: float) -> bool:
	if e.controller.action == null or e.controller.action.id != action:
		if not (e.controller.library as Dictionary).has(action):
			e.controller.add_action(GameData.get_action(action))
		e.controller.force_action(GameData.get_action(action))
	for i in 240:
		await get_tree().process_frame
		var s: Dictionary = e.get_rig_state()
		if int(s.get("phase", 0)) == phase and float(s.get("phase_fraction", 0.0)) >= at:
			await get_tree().process_frame
			return true
		if int(s.get("phase", 0)) > phase and phase != ActionDef.Phase.NONE:
			return false
	return false


static func _joint(rig: PersonRig, bone: String, local := Vector3.ZERO) -> Vector3:
	var m := rig.model()
	var sk := m.skeleton()
	return (m.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))) * local


static func _fist(rig: PersonRig, side: String) -> Vector3:
	var g := PersonRig.grips_of(rig.model().role, rig.model().variant)
	return _joint(rig, "hand_" + side, g["grip_" + side] as Vector3)


## The weapon's line in the world: [grip, unit direction].
static func _weapon(rig: PersonRig) -> Array:
	var sock := rig.weapon_socket()
	return [sock.global_position, sock.global_transform.basis.y.normalized()]


static func _off_line(p: Vector3, line: Array) -> float:
	var d: Vector3 = p - (line[0] as Vector3)
	var u: Vector3 = line[1]
	return (d - u * d.dot(u)).length()


## The actor's front (world, horizontal) and its local frame.
static func _local(e: Node3D, p: Vector3) -> Vector3:
	return e.global_transform.affine_inverse() * p


func test_the_pike_is_drawn_back_then_thrust_level_in_both_hands() -> void:
	PersonRig.enable_for_tests()
	var e := _spawn(PIKEMAN, "test.pike")
	await step_ticks(3)
	var rig := e.rig as PersonRig
	assert_true(rig.skinned(), "skinned")
	assert_true(await _run_to(e, "ability.pike_thrust", ActionDef.Phase.WINDUP, 0.95), "the windup's top")
	var top := _local(e, _fist(rig, "r"))
	var w0: Array = _weapon(rig)
	assert_true(_off_line(_fist(rig, "l"), w0) < GRIP_M, "drawn back: the off fist on the shaft (%.3f m)" % _off_line(_fist(rig, "l"), w0))
	assert_true(await _run_to(e, "ability.pike_thrust", ActionDef.Phase.ACTIVE, 0.6), "the active phase")
	var hit := _local(e, _fist(rig, "r"))
	var w1: Array = _weapon(rig)
	var dir := e.global_transform.basis.inverse() * (w1[1] as Vector3)
	assert_true(hit.z < top.z - 0.2, "thrust: the fist forward of the windup's (%.2f -> %.2f)" % [top.z, hit.z])
	assert_true(dir.z < -0.85 and absf(rad_to_deg(asin(dir.y))) < 25.0, "the pike level at the front (%s)" % dir)
	assert_true(_off_line(_fist(rig, "l"), w1) < GRIP_M, "both fists on the shaft (%.3f m)" % _off_line(_fist(rig, "l"), w1))
	assert_true(_local(e, _fist(rig, "l")).z < hit.z - 0.06, "the off fist ahead of the weapon fist (%.2f m)" % (hit.z - _local(e, _fist(rig, "l")).z))


func test_the_shield_bash_leads_with_the_shield_and_the_brace_squares_it() -> void:
	PersonRig.enable_for_tests()
	var e := _spawn(SHIELDMAN, "test.shield")
	await step_ticks(3)
	var rig := e.rig as PersonRig
	var shield := rig.body.get_node_or_null("Gear_shield") as Node3D
	assert_true(shield != null, "the shield")
	assert_true(await _run_to(e, "ability.shield_bash", ActionDef.Phase.ACTIVE, 0.6), "the bash's active phase")
	var c := _local(e, shield.global_position)
	var chest := _local(e, _joint(rig, "spine_03"))
	var face := (e.global_transform.basis.inverse() * shield.global_transform.basis.z).normalized()
	assert_true(c.z < chest.z - 0.3, "the shield forward of the chest (%.2f m)" % (chest.z - c.z))
	assert_true(face.z < -0.7, "its face to the front (%s)" % face)
	await step_ticks(90)
	assert_true(await _run_to(e, "ability.formation_brace_shield", ActionDef.Phase.ACTIVE, 0.5), "the brace")
	c = _local(e, shield.global_position)
	chest = _local(e, _joint(rig, "spine_03"))
	face = (e.global_transform.basis.inverse() * shield.global_transform.basis.z).normalized()
	assert_true(c.z < chest.z - 0.2 and absf(c.x - chest.x) < 0.25, "squared before the body (%s from the chest)" % (c - chest))
	assert_true(face.z < -0.8, "facing ahead (%s)" % face)


func test_the_archer_kicks_with_a_leg() -> void:
	PersonRig.enable_for_tests()
	var e := _spawn(ARCHER, "test.kick")
	await step_ticks(3)
	var rig := e.rig as PersonRig
	var rest := _local(e, _joint(rig, "foot_r"))
	assert_true(await _run_to(e, "ability.archer_kick", ActionDef.Phase.ACTIVE, 0.6), "the kick")
	var foot := _local(e, _joint(rig, "foot_r"))
	assert_true(foot.y > rest.y + 0.45 and foot.z < rest.z - 0.45, "the foot up and ahead (%s from %s)" % [foot, rest])


func test_the_staff_is_drawn_back_in_two_hands() -> void:
	PersonRig.enable_for_tests()
	var e := _spawn(MAGE, "test.staff")
	await step_ticks(3)
	var rig := e.rig as PersonRig
	assert_true(await _run_to(e, "ability.mage_staff", ActionDef.Phase.WINDUP, 0.95), "the windup's top")
	var w: Array = _weapon(rig)
	var dir := e.global_transform.basis.inverse() * (w[1] as Vector3)
	assert_true(dir.z > 0.2 and dir.y > 0.3, "the staff back over the shoulder (%s)" % dir)
	assert_true(_off_line(_fist(rig, "l"), w) < GRIP_M, "both hands on it (%.3f m)" % _off_line(_fist(rig, "l"), w))


func test_the_pike_brace_grounds_its_butt_and_points_ahead() -> void:
	PersonRig.enable_for_tests()
	var e := _spawn(PIKEMAN, "test.brace")
	await step_ticks(3)
	var rig := e.rig as PersonRig
	assert_true(await _run_to(e, "ability.formation_brace_pike", ActionDef.Phase.ACTIVE, 0.5), "braced")
	var w: Array = _weapon(rig)
	var dir := e.global_transform.basis.inverse() * (w[1] as Vector3)
	var elev := rad_to_deg(asin(dir.y))
	assert_true(dir.z < -0.5 and elev > 20.0 and elev < 55.0, "angled up at the front (%s, %.0f degrees)" % [dir, elev])
	# the butt: the pike mesh's own end behind the grip (it slides back through the fist to the ground)
	var pike := rig.weapon_socket().get_node("Gear_spear") as MeshInstance3D
	var butt := pike.global_transform * Vector3(0.0, pike.mesh.get_aabb().position.y, 0.0)
	assert_true(butt.y - e.global_position.y < 0.15, "the butt on the ground (%.2f m)" % (butt.y - e.global_position.y))
	assert_true(_fist(rig, "r").y - e.global_position.y < 0.95, "the fist low (%.2f m)" % (_fist(rig, "r").y - e.global_position.y))
	assert_true(_off_line(_fist(rig, "l"), w) < GRIP_M, "both fists on it (%.3f m)" % _off_line(_fist(rig, "l"), w))
