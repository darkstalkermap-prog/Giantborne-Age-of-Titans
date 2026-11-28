class_name CinderModel
extends StormcallerModel
## The Cinder Titan (E2, decision E2-1): the Stormcaller's body, skeleton and clips (tools/giant/kit/stormcaller.py's
## asset; no file of his own: the Web pack had no room for a new modelled titan) burned into a giant of his own - his
## skin a charred crust over the fire (cinder_skin.gdshader: the Stormcaller's lightning scars are the furnace showing
## through), his bronze re-cast as black slag with molten seams (cinder_plate.gdshader), and gear made here
## (CinderGear): a crown of slag horns, spines of slag down his back and over his shoulders, and the Cinder-brand - a
## tower-long iron haft with a burning head of fused slag - in place of the storm-rod. The bell, the tined crown, the
## beard and the rod are not drawn. CinderRig scales him to 41.0 m (SCALE: the Stormcaller is 34.0) and poses him by
## the Stormcaller's clips; the model faces +Z.
##
##   CinderModel
##   └ Model                      assets/creatures/stormcaller.glb
##     └ stormcaller_rig
##       ├ Skeleton3D             the clips
##       │ ├ stormcaller          his body (cinder_skin)
##       │ ├ pauldron_l, pauldron_r, lodestone (the heart-coal), bracer, greave_l, greave_r
##       │ │                      the breakable slag (cinder_plate, each its own material: its cracks)
##       │ ├ Head (BoneAttachment3D: head)       horns - the crown plate's slag horns
##       │ ├ Back (BoneAttachment3D: spine_03)   spines - down his back
##       │ ├ ShoulderL/R (upperarm_l/r)          the spines over each shoulder
##       │ └ Brand (BoneAttachment3D: hand_r)    brand - the haft and its head; the head's fire (CinderRig)
##       └ AnimationPlayer
##
## set_heat (1 hot .. 0 quenched) runs through every material: the crust's fire, the slag's seams.

const SCALE := 41.0 / 34.0
const GEAR_SEED := 2026
const HIDDEN := ["beard", "bell", "rod", "crown"]
const SKIN_SHADER := "res://assets/shaders/cinder_skin.gdshader"
const SLAG_SHADER := "res://assets/shaders/cinder_plate.gdshader"
## The plates drawn on the Stormcaller's slabs (the crown is the horns, made here).
const SLABS := ["pauldron_l", "pauldron_r", "lodestone", "bracer", "greave_l", "greave_r"]
const GEAR_PIECES := ["horns", "spines", "spines_l", "spines_r", "brand", "brand_head"]

var heat := 1.0
## The fire on him (his own CinderFx: the brand's head, the heart-coal's lick of flame, his shoulders' smoulder) and its
## light; update_fire places it every frame.
var fire: CinderFx = null
var fire_light: OmniLight3D = null
var _fire_slots: Array = []
var _fire_t := 0.0
var gear_material: ShaderMaterial = null
var brand_head_local := Vector3.ZERO
var brand_axis_local := Vector3.UP
## The gear's nodes (piece name -> its BoneAttachment3D) and bones.
var attachments := {}
var _gear_bone := {"horns": "head", "spines": "spine_03", "spines_l": "upperarm_l", "spines_r": "upperarm_r",
	"brand": "hand_r"}


func build() -> bool:
	if not super():
		return false
	for n: String in HIDDEN:
		if pieces.has(n):
			(pieces[n] as MeshInstance3D).visible = false
			pieces.erase(n)
	body_material = _skin_material(entry())
	body.material_override = body_material
	metal_material = _slag_material(entry())
	plate_materials.clear()
	for n: String in SLABS:
		if pieces.has(n):
			var m := metal_material.duplicate() as ShaderMaterial
			if n == "lodestone":
				m.set_shader_parameter(&"core", 0.6)
			plate_materials[n] = m
			(pieces[n] as MeshInstance3D).material_override = m
	gear_material = metal_material.duplicate() as ShaderMaterial
	var hunch := CinderHunch.new()
	hunch.name = "Hunch"
	skeleton.add_child(hunch)
	_build_gear()
	_build_fire()
	return true


func _skin_material(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SKIN_SHADER)
	for key: String in ["albedo", "normal", "orm"]:
		if ResourceLoader.exists(str(e.get(key, ""))):
			m.set_shader_parameter(StringName(key + "_tex"), load(str(e[key])))
	if ResourceLoader.exists(str(e.get("orm", ""))):
		m.set_shader_parameter(&"band_tex", load(str(e.orm)))
	return m


func _slag_material(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SLAG_SHADER)
	for key: String in ["albedo", "normal"]:
		var path := str(e.get("metal_" + key, ""))
		if ResourceLoader.exists(path):
			m.set_shader_parameter(StringName(key + "_tex"), load(path))
	return m


# --------------------------------------------------------------------------- the gear

func _attach(name: String, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = name
	a.bone_name = bone
	skeleton.add_child(a)
	return a


## A mesh made in model space (the rest pose) under the bone that carries it.
func _hang(piece: String, mesh: ArrayMesh, node_name: String) -> void:
	if mesh == null:
		return
	var bone: String = _gear_bone[piece]
	var i := skeleton.find_bone(bone)
	if i < 0:
		return
	var a := _attach(node_name, bone)
	attachments[piece] = a
	var mi := MeshInstance3D.new()
	mi.name = piece
	mi.mesh = mesh
	mi.material_override = gear_material if piece != "horns" else gear_material.duplicate()
	mi.transform = skeleton.get_bone_global_rest(i).affine_inverse()
	a.add_child(mi)
	pieces[piece] = mi
	if piece == "horns":
		plate_materials[piece] = mi.material_override


func _build_gear() -> void:
	# the crown: two great horns from the temples sweeping out, back and up, and a ring of shorter spikes round the crown
	var g := CinderGear.new(GEAR_SEED)
	var r := g.rng()
	for s: float in [-1.0, 1.0]:
		g.spike(Vector3(1.25 * s, 33.3, 1.2), Vector3(0.85 * s, 0.45, -0.25), 6.4, 0.62, Vector3(0.25 * s, 1.0, -0.55), 8, 8, 0.12)
		g.spike(Vector3(0.95 * s, 32.6, 2.2), Vector3(0.9 * s, -0.1, 0.35), 2.0, 0.3, Vector3(0.6 * s, 0.6, 0.2), 6, 4, 0.2)
	for k in 7:
		var a := lerpf(-2.3, 2.3, float(k) / 6.0)
		var foot := Vector3(sin(a) * 1.15, 34.0 + 0.25 * cos(a), 1.3 + cos(a) * 1.05 - 0.4)
		var out := Vector3(sin(a) * 0.45, 1.0, -0.2 + cos(a) * 0.3)
		g.spike(foot, out, r.randf_range(1.2, 2.4), r.randf_range(0.22, 0.34), Vector3(0, 1, -0.6), 6, 4, 0.25)
	_hang("horns", g.mesh(), "Head")
	# down his back: a ridge of slag spines along the spine and two rows beside it, leaning back and up (his hunched
	# silhouette, where the Stormcaller carried the bell)
	g = CinderGear.new(GEAR_SEED + 1)
	r = g.rng()
	for k in 8:
		var y := lerpf(29.0, 20.5, float(k) / 7.0)
		var z := -2.05 + 0.25 * sin(float(k) * 0.7) - (0.25 if y < 23.0 else 0.0)
		g.spike(Vector3(r.randf_range(-0.15, 0.15), y, z), Vector3(0, 0.55, -1.0), lerpf(3.6, 1.8, float(k) / 7.0) * r.randf_range(0.85, 1.15),
			lerpf(0.65, 0.4, float(k) / 7.0), Vector3(0, 1.0, -0.4), 6, 5, 0.22)
	for s: float in [-1.0, 1.0]:
		for k in 5:
			var y := lerpf(28.0, 21.5, float(k) / 4.0)
			g.spike(Vector3(1.55 * s, y, -1.8), Vector3(0.45 * s, 0.5, -1.0), r.randf_range(1.6, 2.6), r.randf_range(0.3, 0.45),
				Vector3(0.3 * s, 1.0, -0.5), 6, 4, 0.25)
	_hang("spines", g.mesh(), "Back")
	# over each shoulder: three spines out of the slag pauldron
	for s: float in [-1.0, 1.0]:
		g = CinderGear.new(GEAR_SEED + (2 if s > 0 else 3))
		r = g.rng()
		for k in 3:
			var foot := Vector3(3.35 * s + 0.45 * s * float(k), 30.2 - 0.35 * float(k), -0.6 + 0.6 * float(k) - 0.6)
			g.spike(foot, Vector3(0.5 * s, 1.0, -0.35), r.randf_range(2.2, 3.4) * (1.0 - 0.15 * float(k)), r.randf_range(0.38, 0.5),
				Vector3(0.7 * s, 0.6, -0.4), 6, 5, 0.22)
		_hang("spines_l" if s > 0 else "spines_r", g.mesh(), "ShoulderL" if s > 0 else "ShoulderR")
	_build_brand()


## The Cinder-brand in the right hand's frame, along the storm-rod's line (its butt and head from the manifest): an
## iron-shod haft and a head of fused slag and iron, spiked, that burns.
func _build_brand() -> void:
	var rod: Dictionary = (entry().get("pieces", {}) as Dictionary).get("rod", {})
	var hl: Array = rod.get("head_local", [7.3, 7.4, 13.8])
	var bl: Array = rod.get("butt_local", [-9.4, -3.5, -15.8])
	var head := Vector3(float(hl[0]), float(hl[1]), float(hl[2]))
	var butt := Vector3(float(bl[0]), float(bl[1]), float(bl[2]))
	var axis := (head - butt).normalized()
	brand_axis_local = axis
	var i := skeleton.find_bone("hand_r")
	if i < 0:
		return
	var bone_rest := skeleton.get_bone_global_rest(i)
	# built in the hand's own frame, then carried to model space for _hang (which carries it back into the bone)
	var g := CinderGear.new(GEAR_SEED + 9)
	var r := g.rng()
	var xf := bone_rest
	var top := head - axis * 1.4
	g.bar(butt + axis * 0.2, top, 0.42, 0.5, 8, 6, xf)
	# iron bands down the haft
	for k in 5:
		var at := butt.lerp(top, 0.18 + 0.16 * float(k))
		g.bar(at - axis * 0.35, at + axis * 0.35, 0.6, 0.6, 8, 1, xf)
	_hang("brand", g.mesh(), "Brand")
	var haft := pieces.get("brand") as MeshInstance3D
	if haft != null:
		var hm := gear_material.duplicate() as ShaderMaterial
		hm.set_shader_parameter(&"glow_energy", 0.5)
		hm.set_shader_parameter(&"cells", 0.6)
		haft.material_override = hm
	# the head: a heavy mass of slag round the haft's top, a few spikes standing out of it
	g = CinderGear.new(GEAR_SEED + 10)
	r = g.rng()
	var side := axis.cross(Vector3.UP).normalized()
	var up := side.cross(axis).normalized()
	var hb := Basis(side, up, axis)
	var hc := head + axis * 0.4
	g.lump(hc, Vector3(2.3, 2.2, 3.2), hb, 0.16, 12, 18, xf)
	g.lump(hc - axis * 2.4 + side * 0.7, Vector3(1.5, 1.4, 1.3), hb, 0.2, 9, 12, xf)
	g.lump(hc + axis * 1.6 - up * 0.9, Vector3(1.3, 1.2, 1.5), hb, 0.2, 9, 12, xf)
	for k in 4:
		var a := TAU * float(k) / 4.0 + r.randf() * 0.6
		var out := (side * cos(a) + up * sin(a)).normalized()
		var foot := hc + out * 2.0 + axis * r.randf_range(-1.2, 1.5)
		g.spike(foot, (out + axis * r.randf_range(0.0, 0.6)).normalized(), r.randf_range(1.4, 2.2), r.randf_range(0.4, 0.6),
			Vector3.ZERO, 6, 3, 0.25, xf)
	brand_head_local = hc
	_gear_bone["brand_head"] = "hand_r"
	_hang("brand_head", g.mesh(), "BrandHead")
	var mi := pieces.get("brand_head") as MeshInstance3D
	if mi != null:
		var m := gear_material.duplicate() as ShaderMaterial
		m.set_shader_parameter(&"core", 0.55)
		m.set_shader_parameter(&"cells", 1.3)
		mi.material_override = m
		plate_materials["brand_core"] = m


## A point of the brand in the world: its head's middle (`which` "head") or its foot ("butt").
func brand_point(which := "head") -> Vector3:
	var i := skeleton.find_bone("hand_r") if skeleton != null else -1
	if i < 0:
		return global_position
	var local := brand_head_local
	if which != "head":
		var rod: Dictionary = (entry().get("pieces", {}) as Dictionary).get("rod", {})
		var bl: Array = rod.get("butt_local", [0, 0, 0])
		local = Vector3(float(bl[0]), float(bl[1]), float(bl[2]))
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i) * local)


## The brand's axis in the world (from its foot toward its head).
func brand_axis() -> Vector3:
	var i := skeleton.find_bone("hand_r") if skeleton != null else -1
	if i < 0:
		return Vector3.UP
	return ((skeleton.global_transform * skeleton.get_bone_global_pose(i)).basis * brand_axis_local).normalized()


func rod_point(which := "head_local") -> Vector3:
	return brand_point("head" if which == "head_local" else "butt")


# --------------------------------------------------------------------------- the fire on him

## [where (a point in a bone's frame, model units), bone, height m, width m, strength] - the brand's head a crown of
## flames, a lick at the heart-coal, the tips of his back's spines smouldering.
const FIRE_SPOTS := [
	["brand", 0.0, 9.0, 4.2, 1.0], ["brand", 1.0, 7.5, 3.6, 0.9], ["brand", 2.0, 8.5, 4.0, 0.95], ["brand", 3.0, 6.5, 3.2, 0.8],
	["brand", 4.0, 7.0, 3.4, 0.85], ["brand", 5.0, 5.5, 3.0, 0.7],
	["back", 0.0, 4.5, 2.4, 0.5], ["back", 1.0, 3.6, 2.0, 0.45], ["back", 2.0, 3.2, 1.8, 0.4],
]


func _build_fire() -> void:
	fire = CinderFx.new(24, 1)
	fire.name = "Fire"
	add_child(fire)
	_fire_slots.clear()
	for k in FIRE_SPOTS.size():
		_fire_slots.append(fire.add_flame(Vector3(0, -1000, 0), 1.0, 1.0, 0.13 * float(k) + 0.07, 0.0))
	fire_light = OmniLight3D.new()
	fire_light.name = "BrandLight"
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.light_energy = 2.4
	fire_light.omni_range = 34.0
	fire_light.shadow_enabled = false
	add_child(fire_light)


## Places his fire for this frame (`delta` its flicker's clock): flames on the brand's head and its light, a lick at the
## heart-coal (while it is whole), smoulder on his back's spines; all of it lower when he is quenched.
func update_fire(delta: float) -> void:
	if fire == null or skeleton == null:
		return
	_fire_t += delta
	var k := global_transform.basis.get_scale().x
	var head := brand_point("head")
	var axis := brand_axis()
	var side := axis.cross(Vector3.UP).normalized() if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var heart_ok := pieces.has("lodestone") and (pieces["lodestone"] as MeshInstance3D).visible
	var hearth := piece_centre("lodestone") + global_transform.basis.z.normalized() * 1.2 * k if heart_ok else Vector3.ZERO
	var back_i := skeleton.find_bone("spine_03")
	var back_t := skeleton.global_transform * skeleton.get_bone_global_pose(back_i) if back_i >= 0 else global_transform
	var hot := lerpf(0.35, 1.0, heat)
	for n in FIRE_SPOTS.size():
		var spot: Array = FIRE_SPOTS[n]
		var slot: int = _fire_slots[n]
		var j := float(spot[1])
		var at := Vector3.ZERO
		var s := float(spot[4]) * hot
		match str(spot[0]):
			"brand":
				var a := j * TAU / 6.0
				at = head + (side.rotated(axis, a)) * 1.4 * k + axis * (j - 2.5) * 0.4 * k - Vector3.UP * 3.0 * k
			"heart":
				if not heart_ok:
					s = 0.0
				at = hearth + Vector3(j - 0.5, -0.6, 0.0) * k
			"back":
				at = back_t * (Vector3((j - 1.0) * 1.2, 3.5 + j * 1.5, -2.6))
				s *= heat
		var flick := 0.9 + 0.1 * sin(_fire_t * (5.0 + j) + float(n))
		fire.set_flame(slot, at, float(spot[2]) * k * flick, float(spot[3]) * k, 0.13 * float(n) + 0.07, s, 0.6)
	if fire_light != null:
		fire_light.global_position = head + Vector3.UP * 2.0 * k
		fire_light.light_energy = (1.6 + 0.5 * sin(_fire_t * 9.0) * sin(_fire_t * 4.3)) * hot
		fire_light.omni_range = 30.0 * k


# --------------------------------------------------------------------------- his heat, his plates

## His fire (1 hot .. 0 quenched): the crust's cracks, the slag's seams.
func set_heat(amount: float) -> void:
	heat = clampf(amount, 0.0, 1.0)
	if body_material != null:
		body_material.set_shader_parameter(&"heat", heat)
	for m: ShaderMaterial in [metal_material, gear_material]:
		if m != null:
			m.set_shader_parameter(&"heat", heat)
	for n: String in plate_materials:
		(plate_materials[n] as ShaderMaterial).set_shader_parameter(&"heat", heat)
	for n: String in GEAR_PIECES:
		var mi := pieces.get(n) as MeshInstance3D
		if mi != null and mi.material_override is ShaderMaterial:
			(mi.material_override as ShaderMaterial).set_shader_parameter(&"heat", heat)


## (the storm's charge: none in him; his heat is set_heat)
func set_charge(amount: float) -> void:
	charge = clampf(amount, 0.0, 1.0)


func plate_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in SLABS + ["horns"]:
		if pieces.has(n):
			out.append(n)
	return out


func set_plate_crack(name: String, amount: float) -> void:
	var m: ShaderMaterial = plate_materials.get(name)
	if m == null:
		return
	plate_cracks[name] = amount
	m.set_shader_parameter(&"crack", clampf(amount, 0.0, 1.0))


## The bone a piece rides (the gear's own, the slabs' from the manifest).
func gear_bone(name: String) -> String:
	return str(_gear_bone.get(name, StormcallerModel.piece_bone(name)))


## A piece's mesh posed now: the gear rides its bone already (its node's own transform), the slabs as the
## Stormcaller's.
func piece_transform(name: String) -> Transform3D:
	var mi := piece(name)
	if mi == null:
		return global_transform
	if name in GEAR_PIECES:
		return mi.global_transform
	return bone_motion(StormcallerModel.piece_bone(name)) * mi.global_transform
