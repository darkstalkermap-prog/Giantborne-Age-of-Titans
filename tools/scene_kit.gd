class_name SceneKit
extends RefCounted
## Shared kit of the scene builders (plan §2.12): materials, node helpers, the physics-layer
## constants and save(). Each builder in tools/builders/ exposes
##   static func build_all(kit: SceneKit) -> void
## and calls kit.save(root, path) for every scene it makes; tools/build_scenes.gd runs them in
## order. Builders and the kit live in tools/ (never exported); gameplay code must not use them.
##
## save() writes the scene with ResourceSaver, then makes the text deterministic: it removes
## every " unique_id=<n>" attribute Godot 4.6 puts on node lines (random per save; a scene
## without them loads the same) and renumbers the ext_resource / sub_resource ids, which Godot
## draws from a random stream that advances with every save of the process (so an --only build
## and a full build would otherwise disagree). A regenerated scene only differs when its
## content does.
##
## Materials are additive: the shared palette is MATERIALS below, and a builder may add its own
## with add_material() (no edit of this file needed).

const MAT_DIR := "res://assets/materials"

const L_WORLD := 1
const L_ACTORS := 2
const L_HURTBOX := 4
const L_DEBRIS := 8
const L_BREAKABLE := 16
## Invisible movement walls (river banks): actors collide with them; camera, attack occluders,
## line of sight and hurtboxes ignore them (decision 21).
const L_BLOCKER := 32
## The collision mask of every actor body (giant, enemies, NPCs).
const ACTOR_MASK := L_WORLD | L_ACTORS | L_BREAKABLE | L_BLOCKER
## Render layer value for geometry hidden in first person.
const FP_HIDDEN := 2

const S_ENTITY := "res://scripts/combat/combat_entity.gd"
const S_HURTBOX := "res://scripts/combat/hurtbox.gd"
const S_RIG := "res://scripts/presentation/actor_rig.gd"

## The shared palette: name -> [albedo, roughness, metallic].
const MATERIALS := {
	"stone": [Color(0.52, 0.52, 0.55), 0.9, 0.0],
	"stone_dark": [Color(0.38, 0.38, 0.42), 0.9, 0.0],
	"wood": [Color(0.55, 0.38, 0.22), 0.85, 0.0],
	"wood_dark": [Color(0.36, 0.25, 0.15), 0.9, 0.0],
	"giant_skin": [Color(0.78, 0.60, 0.45), 0.8, 0.0],
	"giant_tunic": [Color(0.42, 0.30, 0.20), 0.9, 0.0],
	"giant_belt": [Color(0.22, 0.16, 0.12), 0.8, 0.0],
	"giant_hair": [Color(0.25, 0.17, 0.10), 0.9, 0.0],
	"club": [Color(0.48, 0.33, 0.20), 0.85, 0.0],
	"eyes": [Color(0.08, 0.08, 0.1), 0.6, 0.0],
	"soldier_tabard": [Color(0.70, 0.14, 0.12), 0.85, 0.0],
	"soldier_mail": [Color(0.55, 0.57, 0.60), 0.5, 0.0],
	"soldier_skin": [Color(0.86, 0.68, 0.55), 0.8, 0.0],
	"steel": [Color(0.75, 0.77, 0.80), 0.35, 0.6],
	"sack": [Color(0.66, 0.56, 0.38), 0.95, 0.0],
	"sign_post": [Color(0.3, 0.3, 0.3), 0.9, 0.0],
}

var mats: Dictionary = {}
## Every file save() wrote, in order.
var saved := PackedStringArray()
## "" = scenes go where the builder asks (res://...). Tests set a user:// folder: every saved
## path is then rebased under it, and materials are kept in memory only.
var out_root := ""

var _unique_id_re := RegEx.create_from_string(" unique_id=-?[0-9]+")
var _header_re := RegEx.create_from_string("^\\[(ext_resource|sub_resource) [^\\n]*\\]$")
var _attr_re := RegEx.create_from_string("(\\w+)=\"([^\"]*)\"")
var _ref_re := RegEx.create_from_string("(ExtResource|SubResource)\\(\"([^\"]+)\"\\)")


func _init(p_out_root := "") -> void:
	out_root = p_out_root


## Creates the shared palette (and the ground shader material). With no out_root they are also
## written to assets/materials/<name>.tres.
func make_materials() -> void:
	if out_root == "":
		DirAccess.make_dir_recursive_absolute(MAT_DIR)
	for mat_name: String in MATERIALS:
		var spec: Array = MATERIALS[mat_name]
		add_material(mat_name, spec[0], spec[1], spec[2])
	var ground := ShaderMaterial.new()
	ground.shader = load("res://assets/shaders/ground_checker.gdshader")
	if out_root == "":
		ResourceSaver.save(ground, "%s/ground.tres" % MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)
	mats["ground"] = ground


## Adds (or replaces) one flat-colour material of the palette and returns it.
func add_material(mat_name: String, color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if metallic > 0.0:
		m.metallic = metallic
	if out_root == "":
		ResourceSaver.save(m, "%s/%s.tres" % [MAT_DIR, mat_name], ResourceSaver.FLAG_CHANGE_PATH)
	mats[mat_name] = m
	return m


## Packs `root` (owners set), saves it to `path` (rebased under out_root when set), strips the
## node unique_id attributes, frees `root`. Returns the written path ("" on failure).
func save(root: Node, path: String) -> String:
	own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		push_error("SceneKit: pack failed for %s: %d" % [path, err])
		return ""
	var out_path := output_path(path)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	err = ResourceSaver.save(packed, out_path, ResourceSaver.FLAG_CHANGE_PATH)
	if err == OK:
		err = _strip_file(out_path)
	print("saved %s (%s)" % [out_path, "ok" if err == OK else "error %d" % err])
	if err != OK:
		push_error("SceneKit: could not save %s (error %d)" % [out_path, err])
		return ""
	saved.append(out_path)
	return out_path


## Where save(_, path) writes: `path` itself, or rebased under out_root.
func output_path(path: String) -> String:
	if out_root == "":
		return path
	return out_root.path_join(path.trim_prefix("res://"))


## The text without node unique_id attributes.
func strip_unique_ids(text: String) -> String:
	return _unique_id_re.sub(text, "", true)


## The text with every ext_resource id renumbered "<n>_<first 5 hex of md5(path)>" and every
## sub_resource id "<Type>_<n>" (n counts in file order), references included.
func normalize_resource_ids(text: String) -> String:
	var lines := text.split("\n")
	var mapping := {}   # old id -> new id (ext and sub ids never collide: Godot keeps them apart)
	var ext_n := 0
	var sub_n := 0
	for line in lines:
		var h := _header_re.search(line)
		if h == null:
			continue
		var attrs := {}
		for m in _attr_re.search_all(line):
			attrs[m.get_string(1)] = m.get_string(2)
		if not attrs.has("id"):
			continue
		if h.get_string(1) == "ext_resource":
			ext_n += 1
			mapping[attrs.id] = "%d_%s" % [ext_n, str(attrs.get("path", "")).md5_text().substr(0, 5)]
		else:
			sub_n += 1
			mapping[attrs.id] = "%s_%d" % [str(attrs.get("type", "Resource")), sub_n]
	if mapping.is_empty():
		return text
	for i in lines.size():
		var line := lines[i]
		if _header_re.search(line) != null:
			var id_m := RegEx.create_from_string(" id=\"([^\"]+)\"").search(line)
			if id_m != null and mapping.has(id_m.get_string(1)):
				line = line.substr(0, id_m.get_start(1)) + str(mapping[id_m.get_string(1)]) + line.substr(id_m.get_end(1))
		var refs := _ref_re.search_all(line)
		if not refs.is_empty():
			var out := ""
			var at := 0
			for m in refs:
				out += line.substr(at, m.get_start(2) - at) + str(mapping.get(m.get_string(2), m.get_string(2)))
				at = m.get_end(2)
			line = out + line.substr(at)
		lines[i] = line
	return "\n".join(lines)


func _strip_file(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var text := f.get_as_text()
	f.close()
	var stripped := normalize_resource_ids(strip_unique_ids(text))
	if stripped == text:
		return OK
	f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(stripped)
	f.close()
	return OK


## Loads and instantiates a scene another builder saved earlier in the run (or on an earlier
## run). A missing optional scene returns null after printing a "skipped" note.
func instance(path: String) -> Node:
	var real := output_path(path)
	if not ResourceLoader.exists(real):
		print("SceneKit: skipped %s (not built yet)" % real)
		return null
	return (load(real) as PackedScene).instantiate()


# --------------------------------------------------------------------------- node helpers

func own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			own(child, root)


func scripted(node: Node, script_path: String, props := {}) -> Node:
	node.set_script(load(script_path))
	for k: String in props:
		node.set(k, props[k])
	return node


func n3(node_name: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	return n


func box(node_name: String, size: Vector3, pos: Vector3, mat: String, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mats[mat]
	mi.layers = layers
	return mi


func cyl(node_name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mats[mat]
	return mi


func sphere(node_name: String, r: float, pos: Vector3, mat: String, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mats[mat]
	mi.layers = layers
	return mi


func static_box(node_name: String, size: Vector3, pos: Vector3, mat: String, layer := L_WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(box("Mesh", size, Vector3.ZERO, mat))
	return body


func hurtbox(node_name: String, region: String, shape: Shape3D, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = node_name
	a.position = pos
	a.collision_layer = L_HURTBOX
	a.collision_mask = 0
	a.monitoring = false
	scripted(a, S_HURTBOX, {"region": region})
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	a.add_child(cs)
	return a


func box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


static func arm_basis(yaw_deg: float, pitch_deg: float) -> Basis:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var dir := Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))
	return Basis.looking_at(dir, Vector3.UP)


func sign(text: String, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = "Sign_" + text.get_slice(" ", 0).capitalize()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 12
	l.visibility_range_begin = 7.0   # hide when the camera is right next to it
	l.visibility_range_end = 40.0
	l.modulate = Color(1.0, 0.95, 0.8)
	return l


## The one-box stand-in an enemy shows at AI LOD tier 2 (EnemyActor.set_lod_tier): named
## "LodProxy", hidden until then. Goes under Visual, beside Visual/Body.
func lod_proxy(size: Vector3, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := box("LodProxy", size, pos, mat)
	mi.visible = false
	return mi


## A Marker3D (anchors, spawn points, patrol points).
func marker(node_name: String, pos := Vector3.ZERO) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	m.position = pos
	return m


## The CombatEntity child every combat actor carries.
func combat_entity(entity_id: String, definition_id: String, team: int, anchor := "../Anchors/Torso") -> Node:
	return scripted(Node.new(), S_ENTITY, {"name": "CombatEntity", "entity_id": entity_id,
		"definition_id": definition_id, "team": team, "anchor_path": NodePath(anchor)})


# --------------------------------------------------------------------------- batching (P17b)

## Merges the static meshes below `container` into as few draw calls as their looks allow (P17b,
## FOLLOWUPS: the Valley drew 500-1,350 calls per view, most of them props built from one box per
## plank). Every visible MeshInstance3D reached through unscripted Node3D groups and static bodies
## (not through nodes named in `keep`, hidden ones, scripted ones or other node types) becomes
## part of one ArrayMesh, one surface per material, on a single MeshInstance3D "Merged" per
## (shadow casting, render layers, visibility range) under `container`; SurfaceTool.append_from
## bakes each part's transform (normals included). The merged parts are freed, and so are the
## plain Node3D groups they leave empty. Visibility toggles stay what they were: a breakable's
## Intact / Broken (and a structural prop's stage visuals) are merged one container each. Each
## merged mesh joins `add_groups` (persistent; the prop builders pass LevelRoot's "scenery", so a level's
## graphics preset fades them out with its scenery). Returns how many meshes were merged (0 when
## fewer than two qualify: nothing changes).
func merge_meshes(container: Node3D, keep: PackedStringArray = PackedStringArray(),
		add_groups: PackedStringArray = PackedStringArray()) -> int:
	var found: Array = []   # [MeshInstance3D, Transform3D in container space]
	_collect_meshes(container, Transform3D.IDENTITY, keep, found)
	if found.size() < 2:
		return 0
	var groups := {}        # instance key -> {"mi": template, "mats": {mat key: [Material, parts]}, "order"}
	var group_order: Array = []
	for f: Array in found:
		var mi := f[0] as MeshInstance3D
		var key := "%d|%d|%.2f|%.2f" % [mi.cast_shadow, mi.layers, mi.visibility_range_begin, mi.visibility_range_end]
		if not groups.has(key):
			groups[key] = {"mi": mi, "mats": {}, "order": []}
			group_order.append(key)
		var g: Dictionary = groups[key]
		var mat := _part_material(mi)
		var mkey := mat.resource_path if mat.resource_path != "" else str(mat.get_instance_id())
		if not (g.mats as Dictionary).has(mkey):
			g.mats[mkey] = [mat, []]
			(g.order as Array).append(mkey)
		(g.mats[mkey][1] as Array).append(f)
	var n := 0
	for gi in group_order.size():
		var g: Dictionary = groups[group_order[gi]]
		var mesh := ArrayMesh.new()
		for mkey: String in g.order:
			var entry: Array = g.mats[mkey]
			var st := SurfaceTool.new()
			for part: Array in entry[1]:
				st.append_from((part[0] as MeshInstance3D).mesh, 0, part[1])
				n += 1
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, entry[0])
		var template := g.mi as MeshInstance3D
		var merged := MeshInstance3D.new()
		merged.name = "Merged" if gi == 0 else "Merged%d" % (gi + 1)
		merged.mesh = mesh
		merged.cast_shadow = template.cast_shadow
		merged.layers = template.layers
		merged.visibility_range_begin = template.visibility_range_begin
		merged.visibility_range_end = template.visibility_range_end
		for group: String in add_groups:
			merged.add_to_group(group, true)
		container.add_child(merged)
	for f: Array in found:
		var part := f[0] as MeshInstance3D
		var parent := part.get_parent()
		parent.remove_child(part)
		part.free()
		_prune_empty(parent, container)
	return n


## A part's material: its material_override, else its surface override, else its mesh's own.
static func _part_material(mi: MeshInstance3D) -> Material:
	if mi.material_override != null:
		return mi.material_override
	var m := mi.get_surface_override_material(0)
	return m if m != null else mi.mesh.surface_get_material(0)


func _collect_meshes(node: Node, xf: Transform3D, keep: PackedStringArray, out: Array) -> void:
	for child in node.get_children():
		if not (child is Node3D) or child.get_script() != null or keep.has(String(child.name)) \
				or not (child as Node3D).visible:
			continue
		var cxf := xf * (child as Node3D).transform
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() == 1 and mi.get_child_count() == 0 \
					and _part_material(mi) != null:
				out.append([mi, cxf])
		elif child.get_class() == "Node3D" or child is StaticBody3D:
			_collect_meshes(child, cxf, keep, out)


## Frees `node` and its plain Node3D ancestors below `container` once they have no children left.
func _prune_empty(node: Node, container: Node) -> void:
	var n := node
	while n != null and n != container and n.get_class() == "Node3D" and n.get_child_count() == 0 \
			and n.get_script() == null:
		var parent := n.get_parent()
		parent.remove_child(n)
		n.free()
		n = parent
