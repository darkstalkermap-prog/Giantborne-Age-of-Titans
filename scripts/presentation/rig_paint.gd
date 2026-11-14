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


# --------------------------------------------------------------------------- the mid distance (P30)
# FOLLOWUPS (the M6 gate's "Valley views at low still pass 250 draw calls", assigned to P30): at the
# `low` preset a rig is drawn as one merged mesh of its rest pose ("MidProxy", under Visual/Body)
# from MID_FRACTION x render_lod_m to render_lod_m, between the full rig and the one-box far proxy:
# a soldier then costs one draw call from 20 m instead of six. The renderer swaps them by distance
# with the same 5 m overlap. A rig that acts - an action running, staggered, dead or held - is
# promoted to its full rig out to render_lod_m again (set_mid_active; the rigs call it when that
# changes), so a strike, a stagger, a fall or a grab is never shown frozen. The mesh is built once
# per actor scene from the rig as instanced (its rest pose) and shared; it uses the rig's own
# material copy, so flashes and tints show on it.

const MID_PROXY := "MidProxy"
const MID_FRACTION := 0.45
## Merged rest-pose meshes by actor scene path (shared by every instance of the scene).
static var _mid_meshes := {}


## True when the mid-distance mesh is in use for rigs under `node`: the level's graphics quality is
## `low` (LevelRoot.graphics_quality(); no level: never).
static func mid_lod_wanted(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var lv := node.get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot
	return lv != null and lv.graphics_quality() == "low"


## Sets up the mid distance of the rig `visual` for `lod_m` (see the section notes): its MidProxy
## (the shared rest-pose mesh of `key`, made from `body` when new; the rig's `material`) and the
## parts' range end at the mid distance. Returns the MidProxy (null when lod_m is 0).
static func apply_mid_lod(body: Node3D, lod_m: float, material: Material, key: String) -> MeshInstance3D:
	if body == null or lod_m <= 0.0:
		return null
	var mi := body.get_node_or_null(MID_PROXY) as MeshInstance3D
	var mesh: ArrayMesh = _mid_meshes.get(key) if key != "" else null
	if mesh == null:
		mesh = rest_mesh(body)
		if key != "":
			_mid_meshes[key] = mesh
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MID_PROXY
		body.add_child(mi)
	mi.mesh = mesh
	mi.material_override = material
	mi.visibility_range_begin = maxf(0.0, lod_m * MID_FRACTION - RENDER_LOD_MARGIN_M)
	mi.visibility_range_end = lod_m + RENDER_LOD_MARGIN_M
	set_mid_active(body, true, lod_m)
	return mi


## Takes the mid distance away again (the quality changed): the parts end at lod_m again.
static func remove_mid_lod(body: Node3D, lod_m: float) -> void:
	if body == null:
		return
	var mi := body.get_node_or_null(MID_PROXY) as MeshInstance3D
	if mi == null:
		return
	set_mid_active(body, false, lod_m)
	mi.queue_free()


## active: the parts end at the mid distance and the MidProxy shows beyond it; else (promoted) the
## parts end at lod_m as without a mid distance and the MidProxy is hidden.
static func set_mid_active(body: Node3D, active: bool, lod_m: float) -> void:
	var mid := body.get_node_or_null(MID_PROXY) as MeshInstance3D
	if mid == null:
		return
	var end := (lod_m * MID_FRACTION if active else lod_m) + RENDER_LOD_MARGIN_M
	_set_parts_end(body, end, [body.get_node_or_null(FAR_PROXY), mid])
	mid.visible = active


## One mesh of every visible mesh under `body` (but the proxies) in its current pose, in body space,
## with its vertex colours (a part without them takes its material's albedo).
static func rest_mesh(body: Node3D) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for mi: MeshInstance3D in _rig_meshes(body, body):
		var xf := _relative(mi, body)
		var nb := xf.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pn: Variant = arrays[Mesh.ARRAY_NORMAL]
			var pc: Variant = arrays[Mesh.ARRAY_COLOR]
			var pi: Variant = arrays[Mesh.ARRAY_INDEX]
			var albedo := Color.WHITE
			var mat := mi.material_override as BaseMaterial3D
			if mat == null:
				mat = mi.mesh.surface_get_material(si) as BaseMaterial3D
			if mat != null and not mat.vertex_color_use_as_albedo:
				albedo = mat.albedo_color
			var base := verts.size()
			for i in pv.size():
				verts.append(xf * pv[i])
				normals.append((nb * ((pn as PackedVector3Array)[i] if pn != null and i < (pn as PackedVector3Array).size() else Vector3.UP)).normalized())
				colors.append((pc as PackedColorArray)[i] if pc != null and i < (pc as PackedColorArray).size() else albedo)
			if pi == null or (pi as PackedInt32Array).is_empty():
				for i in pv.size():
					indices.append(base + i)
			else:
				for idx in (pi as PackedInt32Array):
					indices.append(base + idx)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _rig_meshes(node: Node, body: Node3D, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for c in node.get_children():
		if c.name == FAR_PROXY or c.name == MID_PROXY or c.name == LOD_PROXY:
			continue
		if c is Node3D and not (c as Node3D).visible:
			continue
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null:
			out.append(mi)
		_rig_meshes(c, body, out)
	return out


## `node`'s transform in `body`'s space (its parents' local transforms up to body).
static func _relative(node: Node3D, body: Node3D) -> Transform3D:
	var xf := node.transform
	var n := node.get_parent() as Node3D
	while n != null and n != body:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


static func _set_parts_end(node: Node, end_m: float, skip: Array) -> void:
	for child in node.get_children():
		if skip.has(child):
			continue
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).visibility_range_end = end_m
		_set_parts_end(child, end_m, skip)
