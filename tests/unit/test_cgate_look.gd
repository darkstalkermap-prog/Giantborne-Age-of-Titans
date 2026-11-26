extends TestSuite
## The milestone C gate (docs/systems/Cgate.md): the look's defects found by the gate's stills.

const SMOKE := preload("res://tools/world/kinds/smoke.gd")
const FORGE := preload("res://tools/builders/forge.gd")


func _keeps_scale(p: CPUParticles3D) -> bool:
	if p == null or not (p.mesh is QuadMesh):
		return false
	var m := (p.mesh as QuadMesh).material as StandardMaterial3D
	return m != null and m.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES and m.billboard_keep_scale


## G4: the smoke's billboards keep their particle scale - without it the compatibility renderer (the Web's) drew the
## youngest puffs at a fire as one black, opaque blot (Last Hearth's fires, the smithies' chimneys).
func test_the_smoke_keeps_its_puffs_scale() -> void:
	var p := SMOKE.build(null, {"id": "s", "size": [9.0, 2.6]}, {}) as CPUParticles3D
	assert_true(_keeps_scale(p), "the smoke kind's puffs keep their scale")
	assert_true(p.scale_amount_curve != null and p.scale_amount_curve.sample(0.0) < p.scale_amount_curve.sample(1.0),
		"thin at the fire, spreading as it rises")
	p.free()
	var smithy := FORGE.build_smithy()
	var smoke := smithy.get_node_or_null("Smoke") as CPUParticles3D
	assert_true(_keeps_scale(smoke), "the smithy's chimney smoke too")
	smithy.free()
	var built := load("res://scenes/world/smithy.tscn") as PackedScene
	if built != null:
		var inst := built.instantiate()
		assert_true(_keeps_scale(inst.find_child("Smoke", true, false) as CPUParticles3D), "the built smithy scene's smoke")
		inst.free()
