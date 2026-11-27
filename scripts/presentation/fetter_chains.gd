class_name FetterChains
extends Node3D
## E1 (presentation only): the fetters drawn - each chain on the giant (PlayerFetter: rig_state "fetters") a run of heavy
## iron links from the anchor's chain point (a fetter-winch's drum, Orrik's fist) to the giant's ankle (the skeleton's
## foot bone of the chain's leg), hanging in a sag that straightens as it takes his strain. One MultiMesh for every
## chain (two link shapes turned a quarter round each other, alternating); the links' size by the giant's (a colossus's
## chain is as thick as a man). Added by PlayerFetter beside the giant when there is a display; nothing headless.

const MAX_LINKS := 360
## A link's length as a share of the giant's height (stage 8: about 1.2 m) and its thickness of its length.
const LINK_SHARE := 0.042
const THICK_SHARE := 0.32
## The sag at no strain, as a share of the chain's run; a taut chain (strain 1) keeps SAG_TAUT of it.
const SAG := 0.06
const SAG_TAUT := 0.15

var player: GiantPlayer
var _mm: MultiMeshInstance3D
var _mat: StandardMaterial3D


func setup(p: GiantPlayer) -> void:
	player = p
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.17, 0.16, 0.15)
	_mat.metallic = 0.65
	_mat.roughness = 0.45
	var box := BoxMesh.new()
	box.size = Vector3(THICK_SHARE * 1.4, THICK_SHARE * 0.5, 1.05)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = MAX_LINKS
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Links"
	_mm.multimesh = mm
	_mm.material_override = _mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mm.top_level = true
	add_child(_mm)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or _mm == null:
		return
	var f: Variant = player.get("fetter")
	var list: Array = (f as PlayerFetter).fetters if f != null else []
	if list.is_empty():
		_mm.multimesh.visible_instance_count = 0
		return
	var h := float(player.profile.get("height_m", 29.0))
	var link := maxf(0.2, h * LINK_SHARE)
	var n := 0
	var mm := _mm.multimesh
	for c: Dictionary in list:
		var from: Vector3 = c.get("point", Vector3.INF)
		if not from.is_finite():
			continue
		var to := ankle(str(c.get("leg", "l")))
		var run := from.distance_to(to)
		var count := clampi(int(run / link), 2, MAX_LINKS - n)
		var sag := run * SAG * lerpf(1.0, SAG_TAUT, clampf(float(c.get("strain", 0.0)), 0.0, 1.0))
		var prev := from
		for i in count:
			var t := float(i + 1) / count
			var at := from.lerp(to, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
			var mid := (prev + at) * 0.5
			var dir := at - prev
			if dir.length() < 1e-4:
				continue
			var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT)
			if i % 2 == 1:
				basis = basis * Basis(Vector3.BACK, PI * 0.5)
			basis = basis * Basis.from_scale(Vector3.ONE * link)
			mm.set_instance_transform(n, Transform3D(basis, mid))
			n += 1
			prev = at
			if n >= MAX_LINKS:
				break
	mm.visible_instance_count = n


## The giant's ankle of `leg` ("l" | "r"), global: the skeleton's foot bone, else a point by his foot.
func ankle(leg: String) -> Vector3:
	var rig: Variant = player.get("rig")
	var sk: Skeleton3D = rig.call("skeleton") if rig != null and (rig as Object).has_method("skeleton") else null
	if sk != null and sk.is_inside_tree():
		var b := sk.find_bone("foot_l" if leg == "l" else "foot_r")
		if b >= 0:
			return sk.global_transform * sk.get_bone_global_pose(b).origin
	var h := float(player.profile.get("height_m", 29.0))
	return player.global_transform * Vector3((-0.06 if leg == "l" else 0.06) * h, 0.04 * h, 0.0)
