class_name RigPaint
extends RefCounted
## What ActorRig and QuadrupedRig share since P22 (plan M6-M9 §3.4 designs 1 and 2, decision 9):
## the actor's material copies, hit flashes, status tints and the distance level of detail.
## Presentation only.
##
## Materials. A merged rig (SceneKit.merge_rig) is a few vertex-coloured meshes that all use one
## material, so a rig makes one unique copy per source material (unique_copy): one material per
## actor, plus the copies of a weapon visual's own flat materials (the giant's). Every copy has
## emission on from the start, so a flash never changes the shader:
##   * a hit flash sets the emission: flash colour x strength x FLASH_EMISSION (it was a lerp of
##     the albedo toward the flash colour);
##   * a status tint multiplies the albedo: base x white.lerp(tint, tint alpha) (it was a lerp of
##     the albedo toward the tint).
##
## Distance LOD (render_lod_m). Every mesh under Visual/Body gets visibility_range_end =
## render_lod_m + RENDER_LOD_MARGIN_M, and a copy of Visual/LodProxy under Visual/Body ("FarProxy")
## gets visibility_range_begin = render_lod_m - RENDER_LOD_MARGIN_M, so the renderer swaps the rig
## for the one box by distance with a 10 m overlap and never a gap (AI LOD tiers 0 and 1). The
## far proxy lives under Body, so it falls, staggers and hides with the body: at tier 2 (Body
## hidden, Visual/LodProxy shown by the actor) nothing changes. 0 = never (the Ogre King, the
## giant).

const FLASH_EMISSION := 0.85
const RENDER_LOD_MARGIN_M := 5.0
const FAR_PROXY := "FarProxy"
const LOD_PROXY := "LodProxy"


## This rig's copy of `mat`: one per source material (`copies`: source -> copy), with emission on
## and black; a new copy joins `materials` and its albedo colour `base_colors`. A material that is
## already one of the copies is returned as it is.
static func unique_copy(mat: StandardMaterial3D, materials: Array[StandardMaterial3D],
		base_colors: Array[Color], copies: Dictionary) -> StandardMaterial3D:
	if materials.has(mat):
		return mat
	var copy: StandardMaterial3D = copies.get(mat)
	if copy == null:
		copy = mat.duplicate() as StandardMaterial3D
		if not copy.emission_enabled:
			copy.emission_enabled = true
			copy.emission = Color.BLACK
		copies[mat] = copy
		materials.append(copy)
		base_colors.append(copy.albedo_color)
	return copy


## Gives every MeshInstance3D under `node` (material_override StandardMaterial3D) this rig's copy.
static func make_unique(node: Node, materials: Array[StandardMaterial3D], base_colors: Array[Color],
		copies: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mat := mi.material_override as StandardMaterial3D
			if mat != null:
				mi.material_override = unique_copy(mat, materials, base_colors, copies)
		make_unique(child, materials, base_colors, copies)


## Drops the copies the meshes under `node` use (a weapon visual being replaced) from the lists.
static func forget(node: Node, materials: Array[StandardMaterial3D], base_colors: Array[Color],
		copies: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var copy := (child as MeshInstance3D).material_override as StandardMaterial3D
			var idx := materials.find(copy)
			if idx >= 0:
				materials.remove_at(idx)
				base_colors.remove_at(idx)
				for source: Variant in copies.keys():
					if copies[source] == copy:
						copies.erase(source)
		forget(child, materials, base_colors, copies)


## The albedo multiplier of a status tint (rgb = colour, a = strength; alpha 0 = white: none).
static func tint_multiplier(tint: Color) -> Color:
	return Color.WHITE.lerp(Color(tint.r, tint.g, tint.b), clampf(tint.a, 0.0, 1.0))


## The emission of a flash of `strength` (0..1) in `color`.
static func flash_emission(strength: float, color: Color) -> Color:
	var k := maxf(0.0, strength) * FLASH_EMISSION
	return Color(color.r * k, color.g * k, color.b * k)


## Paints the copies: albedo = base x the tint's multiplier, emission = the flash.
static func paint(materials: Array[StandardMaterial3D], base_colors: Array[Color], tint: Color,
		flash: float, flash_color: Color) -> void:
	var mult := tint_multiplier(tint)
	var glow := flash_emission(flash, flash_color)
	for i in materials.size():
		materials[i].albedo_color = base_colors[i] * mult
		materials[i].emission = glow


## Applies the distance LOD of `lod_m` metres to the rig `visual` (its Body and LodProxy, see the
## class notes) and returns the far proxy (null when lod_m is 0, or the rig has no LodProxy).
static func apply_render_lod(visual: Node3D, body: Node3D, lod_m: float) -> MeshInstance3D:
	if body == null:
		return null
	var far := body.get_node_or_null(FAR_PROXY) as MeshInstance3D
	var end := lod_m + RENDER_LOD_MARGIN_M if lod_m > 0.0 else 0.0
	_set_range_end(body, end, far)
	if lod_m <= 0.0:
		if far != null:
			far.visible = false
		return null
	if far == null:
		var proxy := visual.get_node_or_null(LOD_PROXY) as MeshInstance3D
		if proxy == null:
			return null
		far = proxy.duplicate() as MeshInstance3D
		far.name = FAR_PROXY
		# Body sits at the Visual's origin in the rest pose, so the proxy keeps its place.
		far.transform = body.transform.affine_inverse() * proxy.transform
		body.add_child(far)
	far.visible = true
	far.visibility_range_begin = maxf(0.0, lod_m - RENDER_LOD_MARGIN_M)
	far.visibility_range_end = 0.0
	return far


static func _set_range_end(node: Node, end_m: float, skip: Node) -> void:
	for child in node.get_children():
		if child == skip:
			continue
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).visibility_range_end = end_m
		_set_range_end(child, end_m, skip)
