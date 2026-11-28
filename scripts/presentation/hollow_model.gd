class_name HollowModel
extends StormcallerModel
## The Hollow Titan (E3, decision E3-1): the shell of the last giant king - a full harness of plate made here
## (HollowArmour: no file) on the Stormcaller's skeleton, which carries it by his clips and by HollowClips' own (the
## Stormcaller's body, his bronze, his rod and his beard are not drawn: there is nothing inside the armour). HollowRig
## scales him to 39.6 m (SCALE: the Stormcaller is 34.0) and poses him; the model faces +Z.
##
##   HollowModel
##   └ Model                      assets/creatures/stormcaller.glb (its meshes hidden)
##     └ stormcaller_rig
##       ├ Skeleton3D             the clips
##       │ ├ <piece> (BoneAttachment3D: its bone) -> the plate's mesh: the breakable helm (and crown), pauldron_l/r,
##       │ │                      cuirass (the breastplate), vambrace (the sword arm's), greave_l/r; the rest of the
##       │ │                      harness (backplate, faulds, tassets, culet, cuisses, poleyns, sabatons, gorget,
##       │ │                      rerebraces, couters, the left vambrace, gauntlets); the Kingsword in his right hand
##       │ └ Knot (spine_03)      the oath-knot: a ball of chain in his breast, the strands of chain from it into the
##       │                        shell, its light (pale gold: hollow_knot.gdshader, an OmniLight)
##       └ AnimationPlayer        the Stormcaller's library and his own (HollowClips.LIBRARY)
##
## set_resonance (his echo), set_life (his fall: the light going out of him), set_knot_bare (the breastplate off).

const SCALE := 39.6 / 34.0
const ARMOUR_SHADER := "res://assets/shaders/hollow_armour.gdshader"
const KNOT_SHADER := "res://assets/shaders/hollow_knot.gdshader"
## The Stormcaller's pieces, none drawn.
const HIDDEN := ["beard", "bell", "rod", "crown", "pauldron_l", "pauldron_r", "lodestone", "bracer", "greave_l", "greave_r"]
## The plates that break (the record's pieces).
const PLATE_PIECES := ["helm", "pauldron_l", "pauldron_r", "cuirass", "vambrace", "greave_l", "greave_r"]
## The oath-knot in his breast (model space).
const KNOT_AT := Vector3(0.0, 24.4, 1.4)
const BLADE_M := 15.5

var resonance := 0.0
var life := 1.0
var knot_bare := false
var armour_material: ShaderMaterial = null
var knot_material: ShaderMaterial = null
## The oath-chains' links (HollowRig): the armour's iron.
var chain_material: ShaderMaterial = null
var knot_light: OmniLight3D = null
## Piece name -> its bone; the gear's attachments.
var piece_bones := {}
var attachments := {}
var sword_tip_local := Vector3.ZERO
var sword_hilt_local := Vector3.ZERO
var triangle_count := 0


func build() -> bool:
	if not super():
		return false
	body.visible = false
	for n: String in pieces.keys():
		(pieces[n] as MeshInstance3D).visible = false
	pieces.clear()
	plate_materials.clear()
	armour_material = ShaderMaterial.new()
	armour_material.shader = load(ARMOUR_SHADER)
	armour_material.set_shader_parameter(&"knot_pos", KNOT_AT)
	chain_material = armour_material.duplicate() as ShaderMaterial
	chain_material.set_shader_parameter(&"seed_offset", 3.7)
	_build_harness()
	_build_sword()
	_build_knot()
	HollowClips.install(self)
	pose("idle", 0.0)
	return true


# --------------------------------------------------------------------------- frames

## A bone's rest frame in model space.
func rest(bone: String) -> Transform3D:
	var i := skeleton.find_bone(bone)
	return skeleton.get_bone_global_rest(i) if i >= 0 else Transform3D.IDENTITY


## A section ring round bone `bone`'s axis `t` m along it, its half-axes along the bone's x and z, its centre moved by
## `off` (bone frame).
func bring(bone: String, t: float, rx: float, rz: float, gilt := 0.0, off := Vector3.ZERO, extra := Callable()) -> Array:
	var f := rest(bone)
	return HollowArmour.ring(f * (Vector3(0, t, 0) + off), f.basis.x, f.basis.z, rx, rz, gilt, extra)


## A section ring in model space at height `y` round the body's axis (x his left, z his front).
static func mring(y: float, rx: float, rz: float, zc := 0.0, gilt := 0.0, xc := 0.0, extra := Callable()) -> Array:
	return HollowArmour.ring(Vector3(xc, y, zc), Vector3.RIGHT, Vector3.BACK, rx, rz, gilt, extra)


static func ridge(at: float, height: float, width := 0.28) -> Callable:
	return func(a: float) -> float:
		var d := wrapf(a - at, -PI, PI)
		return height * exp(-(d / width) * (d / width))


## Hangs a mesh made in model space (the rest pose) under the bone that carries it.
func _hang(piece: String, ab: HollowArmour, bone: String, breakable := false) -> MeshInstance3D:
	var mesh := ab.mesh()
	var i := skeleton.find_bone(bone)
	if mesh == null or i < 0:
		return null
	triangle_count += ab.triangles()
	var key := bone
	var a: BoneAttachment3D = attachments.get(key)
	if a == null:
		a = BoneAttachment3D.new()
		a.name = "On_" + bone
		a.bone_name = bone
		skeleton.add_child(a)
		attachments[key] = a
	var mi := MeshInstance3D.new()
	mi.name = piece
	mi.mesh = mesh
	mi.transform = skeleton.get_bone_global_rest(i).affine_inverse()
	if breakable:
		var m := armour_material.duplicate() as ShaderMaterial
		plate_materials[piece] = m
		mi.material_override = m
	else:
		mi.material_override = armour_material
	a.add_child(mi)
	pieces[piece] = mi
	piece_bones[piece] = bone
	return mi


func _ab(t := 0.5) -> HollowArmour:
	var ab := HollowArmour.new()
	ab.tone = t
	return ab


# --------------------------------------------------------------------------- the harness

func _build_harness() -> void:
	var front := PI * 0.5
	var back := -PI * 0.5
	# the breastplate: from the waist to the collar, round his front past his flanks, a ridge down its middle
	var ab := _ab(0.55)
	var r := ridge(front, 0.22, 0.3)
	ab.loft([mring(21.0, 2.95, 2.55, 0.25, 1.0, 0.0, r), mring(21.5, 3.0, 2.7, 0.3, 0.35, 0.0, r),
		mring(23.0, 3.15, 3.0, 0.4, 0.0, 0.0, r), mring(24.8, 3.45, 3.3, 0.45, 0.0, 0.0, r),
		mring(26.4, 3.55, 3.25, 0.45, 0.0, 0.0, r), mring(27.6, 3.4, 2.95, 0.4, 0.0, 0.0, r),
		mring(28.5, 2.85, 2.4, 0.35, 0.3, 0.0, r), mring(29.0, 2.35, 2.0, 0.3, 1.0, 0.0, r)],
		front - 1.95, front + 1.95, 30, 0.3, Transform3D.IDENTITY, 1.0)
	_hang("cuirass", ab, "spine_03", true)
	# the backplate: round his back, its top standing up behind the neck
	ab = _ab(0.45)
	r = ridge(back, 0.12, 0.25)
	ab.loft([mring(21.1, 3.05, 2.65, 0.2, 1.0, 0.0, r), mring(23.0, 3.25, 3.05, 0.25, 0.0, 0.0, r),
		mring(25.0, 3.6, 3.3, 0.3, 0.0, 0.0, r), mring(27.0, 3.6, 3.15, 0.35, 0.0, 0.0, r),
		mring(28.7, 2.9, 2.5, 0.35, 0.0, 0.0, r), mring(29.9, 2.25, 2.05, 0.2, 1.0, 0.0, r)],
		back - 1.85, back + 1.85, 26, 0.28, Transform3D.IDENTITY, 1.0)
	_hang("backplate", ab, "spine_03")
	# the faulds: two lames round the belly and the small of his back, each over the one below
	ab = _ab(0.4)
	ab.loft([mring(20.0, 3.05, 2.7, 0.2, 0.2), mring(21.35, 3.0, 2.62, 0.25, 0.0)], 0.0, TAU, 32, 0.22)
	ab.loft([mring(18.9, 3.2, 2.85, 0.15, 1.0), mring(20.25, 3.12, 2.76, 0.2, 0.0)], 0.0, TAU, 32, 0.22)
	_hang("faulds", ab, "spine_01")
	# the tassets over his thighs (three lames each) and the culet over his seat
	ab = _ab(0.5)
	for s: float in [1.0, -1.0]:
		var u := Vector3(s, 0, 0)
		var lames := [[18.9, 17.3, 2.45], [17.6, 15.9, 2.6], [16.2, 14.4, 2.75]]
		for l: Array in lames:
			var c0 := Vector3(1.95 * s, float(l[0]), 0.35)
			var c1 := Vector3(2.15 * s, float(l[1]), 0.55)
			var rr := float(l[2])
			ab.loft([HollowArmour.ring(c0, u, Vector3.BACK, rr - 0.12, rr * 0.92, 0.0),
				HollowArmour.ring(c1, u, Vector3.BACK, rr + 0.1, rr * 0.98, 1.0)], -0.55, 2.0, 12, 0.18, Transform3D.IDENTITY, 0.6)
	ab.loft([mring(19.2, 3.25, 2.9, 0.0, 0.0), mring(17.0, 3.5, 3.15, -0.2, 1.0)], back - 1.05, back + 1.05, 14, 0.2,
		Transform3D.IDENTITY, 0.6)
	_hang("tassets", ab, "pelvis")
	for side: String in ["l", "r"]:
		# the cuisses: open at the back of the thigh
		var thigh := "thigh_" + side
		ab = _ab(0.5)
		var rf := ridge(-PI * 0.5, 0.18, 0.35)
		ab.loft([bring(thigh, 1.4, 2.0, 2.05, 0.0, Vector3.ZERO, rf), bring(thigh, 3.2, 2.05, 2.1, 0.0, Vector3.ZERO, rf),
			bring(thigh, 5.4, 1.8, 1.85, 0.0, Vector3.ZERO, rf), bring(thigh, 7.1, 1.5, 1.55, 1.0, Vector3.ZERO, rf)],
			PI * 0.5 + 0.6, PI * 0.5 + TAU - 0.6, 22, 0.2, Transform3D.IDENTITY, 0.5)
		_hang("cuisse_" + side, ab, thigh)
		# the poleyn over the knee and its fan
		var calf := "calf_" + side
		ab = _ab(0.6)
		var kf := -PI * 0.5
		ab.loft([bring(calf, -1.3, 0.5, 0.5, 0.0, Vector3(0, 0, -0.9)), bring(calf, -0.9, 1.35, 1.25, 0.0, Vector3(0, 0, -0.5)),
			bring(calf, -0.1, 1.75, 1.6, 0.0, Vector3(0, 0, -0.3)), bring(calf, 0.7, 1.6, 1.45, 0.0, Vector3(0, 0, -0.25)),
			bring(calf, 1.2, 1.4, 1.3, 1.0, Vector3(0, 0, -0.2))], kf - 1.75, kf + 1.75, 16, 0.2, Transform3D.IDENTITY, 1.0)
		_hang("poleyn_" + side, ab, calf)
		# the greave: closed round the shin, a ridge down its front, gilt at its top
		ab = _ab(0.5)
		var rg := ridge(-PI * 0.5, 0.14, 0.3)
		ab.loft([bring(calf, 1.0, 1.5, 1.55, 1.0, Vector3(0, 0, 0.05), rg), bring(calf, 2.6, 1.62, 1.75, 0.0, Vector3(0, 0, 0.15), rg),
			bring(calf, 4.6, 1.5, 1.6, 0.0, Vector3(0, 0, 0.1), rg), bring(calf, 6.6, 1.25, 1.3, 0.0, Vector3.ZERO, rg),
			bring(calf, 8.4, 1.18, 1.22, 1.0, Vector3.ZERO, rg)], 0.0, TAU, 26, 0.24)
		_hang("greave_" + side, ab, calf, true)
		# the sabaton: over the foot (open under it), lames to the toe
		var foot := "foot_" + side
		ab = _ab(0.45)
		var top := -PI * 0.5
		ab.loft([bring(foot, -1.0, 1.1, 1.35, 1.0, Vector3(0, 0, -0.1)), bring(foot, 0.4, 1.3, 1.35),
			bring(foot, 1.8, 1.3, 1.0, 0.0, Vector3(0, 0, -0.2)), bring(foot, 3.0, 1.15, 0.75, 1.0, Vector3(0, 0, -0.4))],
			top - 2.2, top + 2.2, 16, 0.18, Transform3D.IDENTITY, 0.0)
		_hang("sabaton_" + side, ab, foot)
		var ball := "ball_" + side
		ab = _ab(0.45)
		ab.loft([bring(ball, -0.3, 1.15, 0.75, 0.0, Vector3(0, 0, -0.35)), bring(ball, 0.8, 1.05, 0.62, 0.0, Vector3(0, 0, -0.3)),
			bring(ball, 1.7, 0.62, 0.4, 1.0, Vector3(0, 0, -0.2))], -PI * 0.5 - 2.0, -PI * 0.5 + 2.0, 12, 0.16)
		_hang("toe_" + side, ab, ball)
		_arm(side)
	# the gorget round his neck, flaring onto the shoulders
	ab = _ab(0.5)
	ab.loft([bring("neck_01", -1.4, 2.65, 2.45, 1.0, Vector3(0, 0, -0.1)), bring("neck_01", -0.7, 2.1, 2.0, 0.0),
		bring("neck_01", 0.5, 1.75, 1.75, 0.0, Vector3(0, 0, 0.2)), bring("neck_01", 1.15, 1.68, 1.7, 1.0, Vector3(0, 0, 0.25))],
		0.0, TAU, 28, 0.2)
	_hang("gorget", ab, "neck_01")
	_helm()
	_mantle()


## The mantle: a king's cloak hung from his shoulders down his back to his thighs, its hem torn ragged (cloth: its own
## material, both faces drawn).
func _mantle() -> void:
	var ab := _ab(0.5)
	var rows := 9
	var cols := 18
	var back := -PI * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 4402
	var hem: Array[float] = []
	for k in cols + 1:
		hem.append(rng.randf_range(0.0, 3.6) * (0.4 + 0.6 * absf(sin(float(k) * 1.7))))
	var grid: Array = []
	for i in rows:
		var f := float(i) / float(rows - 1)
		var row: Array[Vector3] = []
		for k in cols + 1:
			var y := lerpf(29.6, 11.5, f)
			if i == rows - 1:
				y += hem[k]
			elif i == rows - 2:
				y += hem[k] * 0.35
			var g := clampf((29.6 - y) / 18.0, 0.0, 1.0)
			var rx := lerpf(3.05, 4.9, pow(g, 0.8))
			var rz := lerpf(2.75, 4.4, pow(g, 0.8))
			var zc := lerpf(0.1, -1.4, g)
			var a := back + lerpf(-1.75, 1.75, float(k) / float(cols)) * lerpf(1.0, 0.92, g)
			var fold := 0.18 * sin(float(k) * 2.4) * g
			row.append(Vector3(cos(a) * (rx + fold), y, zc + sin(a) * (rz + fold)))
		grid.append(row)
	ab.sheet(grid, false, 0.12, [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, 0.08)
	var mi := _hang("mantle", ab, "spine_03")
	if mi != null:
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color(0.2, 0.075, 0.06)
		cloth.roughness = 0.97
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = cloth


## The helm: a great helm closed round an empty head, its eye-slit open on the dark, a ridge down its face, the crown
## on it (one piece: they break together).
func _helm() -> void:
	var ab := _ab(0.6)
	var face := PI * 0.5
	var rf := ridge(face, 0.2, 0.2)
	var o := Vector3(0, 0, 0.35)
	ab.loft([bring("head", -1.75, 1.85, 2.0, 1.0, o + Vector3(0, 0, -0.1), rf), bring("head", -0.9, 1.95, 2.2, 0.0, o, rf),
		bring("head", -0.1, 2.02, 2.3, 0.0, o, rf), bring("head", 0.42, 2.04, 2.32, 0.5, o, rf)], 0.0, TAU, 30, 0.22)
	ab.loft([bring("head", 0.74, 2.04, 2.32, 0.5, o, rf), bring("head", 1.5, 1.98, 2.24, 0.0, o, rf),
		bring("head", 2.25, 1.75, 1.95, 0.0, o, rf), bring("head", 2.75, 1.3, 1.45, 0.0, o, rf),
		bring("head", 3.05, 0.75, 0.85, 0.0, o), bring("head", 3.2, 0.15, 0.18, 0.0, o)], 0.0, TAU, 30, 0.22)
	# the slit's back: closed behind the eyes
	ab.loft([bring("head", 0.38, 2.04, 2.32, 0.0, o, rf), bring("head", 0.78, 2.04, 2.32, 0.0, o, rf)],
		face + 0.75, face + TAU - 0.75, 22, 0.22)
	# the crown: a gilt circlet and its tines, the front one tallest
	var f := rest("head")
	ab.loft([bring("head", 2.05, 1.95, 2.17, 1.0, o), bring("head", 2.6, 2.0, 2.22, 1.0, o)], 0.0, TAU, 30, 0.12)
	for k in 9:
		var a := face + TAU * float(k) / 9.0
		var dir_l := Vector3(cos(a) * 2.0, 0.0, sin(a) * 2.22)
		var base := f * (Vector3(0, 2.5, 0) + o + dir_l)
		var out := (f.basis * (dir_l.normalized() * 0.28 + Vector3.UP)).normalized()
		var tall := 2.4 if k == 0 else (1.5 if k % 2 == 0 else 1.1)
		ab.spike(base, out, tall, 0.32 if k == 0 else 0.24, 1.0, 7)
	_hang("helm", ab, "head", true)


## An arm's harness: the pauldron (three lames over the shoulder), the rerebrace, the couter, the vambrace and the
## gauntlet.
func _arm(side: String) -> void:
	var up := "upperarm_" + side
	var low := "lowerarm_" + side
	var hand := "hand_" + side
	var ab := _ab(0.55)
	# the lames: the arm's outer side all round but the armpit (the bone's +x points to the body's side, down)
	var a0 := 1.0
	var a1 := TAU - 1.0
	ab.loft([bring(up, -1.7, 0.9, 0.95, 0.0, Vector3(0.35, 0, 0)), bring(up, -1.1, 2.0, 2.05, 0.0, Vector3(0.2, 0, 0)),
		bring(up, -0.3, 2.45, 2.5), bring(up, 0.7, 2.55, 2.6, 0.0), bring(up, 1.05, 2.58, 2.62, 1.0)], a0, a1, 22, 0.24,
		Transform3D.IDENTITY, 1.0)
	ab.loft([bring(up, 0.75, 2.4, 2.45), bring(up, 1.95, 2.62, 2.66, 1.0)], a0 + 0.1, a1 - 0.1, 20, 0.22,
		Transform3D.IDENTITY, 0.6)
	ab.loft([bring(up, 1.7, 2.3, 2.35), bring(up, 2.8, 2.45, 2.5, 1.0)], a0 + 0.2, a1 - 0.2, 20, 0.22,
		Transform3D.IDENTITY, 0.6)
	_hang("pauldron_" + side, ab, up, true)
	ab = _ab(0.45)
	ab.loft([bring(up, 2.6, 1.3, 1.3), bring(up, 3.8, 1.2, 1.22), bring(up, 4.7, 1.1, 1.12, 1.0)], 0.0, TAU, 18, 0.18)
	_hang("rerebrace_" + side, ab, up)
	ab = _ab(0.6)
	ab.loft([bring(low, -1.0, 0.7, 0.7), bring(low, -0.5, 1.4, 1.35), bring(low, 0.3, 1.45, 1.4),
		bring(low, 0.9, 1.15, 1.12, 1.0)], 0.0, TAU, 18, 0.18)
	_hang("couter_" + side, ab, low)
	ab = _ab(0.5)
	ab.loft([bring(low, 0.8, 1.12, 1.06), bring(low, 2.4, 1.15, 1.08), bring(low, 4.0, 0.98, 0.92),
		bring(low, 5.0, 0.95, 0.9, 1.0)], 0.0, TAU, 20, 0.2)
	_hang("vambrace" if side == "r" else "vambrace_l", ab, low, side == "r")
	ab = _ab(0.5)
	ab.loft([bring(hand, -0.4, 1.3, 1.2, 1.0), bring(hand, 0.5, 1.12, 1.0)], 0.0, TAU, 18, 0.16)
	ab.loft([bring(hand, 0.4, 1.0, 0.6), bring(hand, 1.5, 1.05, 0.62), bring(hand, 2.5, 0.98, 0.55, 0.6)], 0.0, TAU, 16, 0.16)
	ab.loft([bring(hand, 2.35, 0.95, 0.55), bring(hand, 3.0, 0.9, 0.52), bring(hand, 3.5, 0.7, 0.42)], 0.0, TAU, 14, 0.14)
	_hang("gauntlet_" + side, ab, hand)


# --------------------------------------------------------------------------- the Kingsword

## The Kingsword in his right hand, along the rod's line (the clips hold the rod: the hilt in his fist, the blade toward
## the rod's head).
func _build_sword() -> void:
	var rod: Dictionary = (entry().get("pieces", {}) as Dictionary).get("rod", {})
	var hl: Array = rod.get("head_local", [7.3, 7.4, 13.8])
	var bl: Array = rod.get("butt_local", [-9.4, -3.5, -15.8])
	var head := Vector3(float(hl[0]), float(hl[1]), float(hl[2]))
	var butt := Vector3(float(bl[0]), float(bl[1]), float(bl[2]))
	var axis := (head - butt).normalized()
	# the grip: the rod's point nearest the palm
	var palm := Vector3(0, 1.3, 0)
	var grip := butt + axis * (palm - butt).dot(axis)
	var xf := rest("hand_r")
	var ab := _ab(0.97)
	var guard := grip + axis * 1.35
	var edge := Vector3.RIGHT - axis * Vector3.RIGHT.dot(axis)
	edge = edge.normalized()
	var flat := axis.cross(edge).normalized()
	ab.blade(guard + axis * 0.2, axis, edge, BLADE_M, 1.7, 0.55, 0.42, xf)
	# the guard's bar, its quillons turned toward the blade, the grip and the pommel
	ab.box(guard, edge * 2.4, axis * 0.28, flat * 0.36, 1.0, xf)
	ab.spike(guard + edge * 2.3, (edge + axis * 0.6).normalized(), 0.9, 0.3, 1.0, 6, xf)
	ab.spike(guard - edge * 2.3, (-edge + axis * 0.6).normalized(), 0.9, 0.3, 1.0, 6, xf)
	var g0 := grip - axis * 1.5
	ab.loft([HollowArmour.ring(g0, edge, flat, 0.46, 0.46), HollowArmour.ring(guard, edge, flat, 0.42, 0.42)], 0.0, TAU,
		10, 0.1, xf)
	var pm := grip - axis * 1.9
	ab.loft([HollowArmour.ring(pm - axis * 0.6, edge, flat, 0.25, 0.25, 1.0), HollowArmour.ring(pm - axis * 0.3, edge,
		flat, 0.65, 0.65, 1.0), HollowArmour.ring(pm + axis * 0.2, edge, flat, 0.7, 0.7, 1.0), HollowArmour.ring(pm + axis
		* 0.5, edge, flat, 0.35, 0.35, 1.0)], 0.0, TAU, 12, 0.3, xf)
	sword_hilt_local = guard
	sword_tip_local = guard + axis * (BLADE_M + 0.2)
	_hang("kingsword", ab, "hand_r")


## A point of the sword in the world: its tip ("head_local", as the rod's head is read) or its hilt.
func rod_point(which := "head_local") -> Vector3:
	var i := skeleton.find_bone("hand_r") if skeleton != null else -1
	if i < 0:
		return global_position
	var local := sword_tip_local if which == "head_local" else sword_hilt_local
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i) * local)


# --------------------------------------------------------------------------- the oath-knot

func _build_knot() -> void:
	knot_material = ShaderMaterial.new()
	knot_material.shader = load(KNOT_SHADER)
	var ab := _ab(0.5)
	# a ball of chain: three loops round the knot's middle, turned to each other, and a fourth through them
	var c := KNOT_AT
	for k in 4:
		var pts := PackedVector3Array()
		var axis := [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1, 1, 0).normalized()][k] as Vector3
		var u := axis.cross(Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var v := axis.cross(u).normalized()
		var rr := 1.05 + 0.12 * float(k)
		for s in 17:
			var a := TAU * float(s) / 16.0
			pts.append(c + (u * cos(a) + v * sin(a)) * rr)
		ab.chain(pts, 0.95, 0.62, 0.13)
	# the strands from it into the shell: up the neck into the helm, to each shoulder, down to the hips, to the back
	for end: Vector3 in [Vector3(0, 29.6, 0.6), Vector3(2.9, 27.7, 0.4), Vector3(-2.9, 27.7, 0.4), Vector3(0.6, 19.6, 0.4),
			Vector3(-0.7, 20.1, -0.2), Vector3(0, 25.4, -1.9)]:
		var mid := c.lerp(end, 0.5) + Vector3(0, -0.5, 0)
		var pts := PackedVector3Array([c + (end - c).normalized() * 1.1, mid, end])
		ab.chain(pts, 0.9, 0.58, 0.12)
	var mi := _hang("knot", ab, "spine_03")
	if mi != null:
		mi.material_override = knot_material
	knot_light = OmniLight3D.new()
	knot_light.name = "KnotLight"
	knot_light.light_color = Color(1.0, 0.72, 0.38)
	knot_light.omni_range = 9.0
	knot_light.light_energy = 1.0
	knot_light.shadow_enabled = false
	var a: BoneAttachment3D = attachments.get("spine_03")
	if a != null:
		a.add_child(knot_light)
		knot_light.transform = Transform3D(Basis(), skeleton.get_bone_global_rest(skeleton.find_bone("spine_03")).affine_inverse() * c)
	_update_knot()


func _update_knot() -> void:
	var glow := life * (1.0 if knot_bare else 0.55) * (0.8 + 0.4 * resonance)
	if knot_material != null:
		knot_material.set_shader_parameter(&"glow", glow)
		knot_material.set_shader_parameter(&"life", life)
	if knot_light != null:
		knot_light.light_energy = glow * (1.6 if knot_bare else 0.7)
		knot_light.omni_range = 8.0 if knot_bare else 5.5
		knot_light.visible = life > 0.02


# --------------------------------------------------------------------------- his state

func _set_all(param: StringName, value: Variant) -> void:
	if armour_material != null:
		armour_material.set_shader_parameter(param, value)
	for n: String in plate_materials:
		(plate_materials[n] as ShaderMaterial).set_shader_parameter(param, value)


## His echo (0..1): the shell's edges shimmer as it fills.
func set_resonance(amount: float) -> void:
	resonance = clampf(amount, 0.0, 1.0)
	_set_all(&"resonance", resonance)
	_update_knot()


## His life (1 .. 0 at his fall): the knot's light going out of the shell.
func set_life(amount: float) -> void:
	life = clampf(amount, 0.0, 1.0)
	_set_all(&"life", life)
	_update_knot()


func set_knot_bare(on: bool) -> void:
	knot_bare = on
	_update_knot()


## (no storm in him: the charge is the knot's own)
func set_charge(amount: float) -> void:
	charge = clampf(amount, 0.0, 1.0)


func plate_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in PLATE_PIECES:
		if pieces.has(n):
			out.append(n)
	return out


func set_plate_crack(name: String, amount: float) -> void:
	var m: ShaderMaterial = plate_materials.get(name)
	if m == null:
		return
	plate_cracks[name] = amount
	m.set_shader_parameter(&"crack", clampf(amount, 0.0, 1.0))


## The bone a piece rides.
func gear_bone(name: String) -> String:
	return str(piece_bones.get(name, "spine_03"))


## A piece's mesh posed now: it rides its bone already (its node's own transform).
func piece_transform(name: String) -> Transform3D:
	var mi := piece(name)
	return mi.global_transform if mi != null else global_transform


func piece_centre(name: String) -> Vector3:
	var mi := piece(name)
	if mi == null or mi.mesh == null:
		return global_position + Vector3.UP * 20.0
	return mi.global_transform * mi.mesh.get_aabb().get_center()


## Every piece of the harness (the death's collapse throws them all).
func harness_pieces() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in pieces:
		out.append(n)
	return out


func clip_length(name: String) -> float:
	var own := HollowClips.length_of(self, name)
	return own if own > 0.0 else super(name)


func has_clip(name: String) -> bool:
	return HollowClips.has(self, name) or super(name)


func pose(name: String, t: float) -> void:
	if HollowClips.has(self, name):
		clip = name
		clip_time = clampf(t, 0.0, clip_length(name))
		var full := StringName(String(HollowClips.LIBRARY) + "/" + name)
		player.play(full)
		player.seek(clip_time, true)
		player.advance(0.0)
		return
	super(name, t)
