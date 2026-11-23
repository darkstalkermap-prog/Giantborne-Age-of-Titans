class_name RootwardenModel
extends Node3D
## The Rootwarden (B3): his model as the asset pipeline made it (tools/giant/kit/rootwarden.py), posed by clip and
## time - RootwardenRig poses it under his actor, the stills and the cutscene pose it alone. 21.3 m to the top of his
## head (24 m to his antlers' tips) in his file; the model faces +Z.
##
##   RootwardenModel
##   └ Model                      assets/creatures/rootwarden.glb
##     └ rootwarden_rig           the armature
##       ├ Skeleton3D             23 bones (the people's): the clips (rootwarden_clips.glb)
##       │ ├ rootwarden           his body of bark-skin, the moss skirt (person.gdshader on his atlas)
##       │ ├ bark_<plate>         the breakable bark plates, each its own mesh (stone_plate.gdshader on the bark
##       │ │                      texture; their fungi and the knot's sap seams glow): shoulder_l, shoulder_r, back,
##       │ │                      forearm_r, shin_l, shin_r, knot
##       │ ├ sap_bark_<plate>     the sapwood under each plate (glowing amber): shown while its plate is gone
##       │ ├ roots                the root-arm's roots, the antlers, the dead tree (shown in the rip and the hurl)
##       └ AnimationPlayer        manual: pose(clip, time)
##
## Each plate has its own material, so it shows its state alone: split along its grain as its bark wears
## (set_plate_crack), regrowing over its wound (set_plate_grow: eaten away, fresh bark at the edge), gone
## (set_plate_visible: the rig drops a copy of it and shows the sapwood); a seared wound's sapwood chars
## (set_sap_char: black, embers, no glow).

const CREATURE := "rootwarden"
const MODEL_NAME := "Model"
const LIBRARY := &"rootwarden"
const SHADER := "res://assets/shaders/stone_plate.gdshader"
const PLATES := ["bark_shoulder_l", "bark_shoulder_r", "bark_back", "bark_forearm_r", "bark_shin_l", "bark_shin_r",
	"bark_knot"]
const CRACK_AT := 0.6
const BADLY_AT := 0.3
const CRACKED := 0.5
const BADLY_CRACKED := 0.9
## His colours: grey-brown bark-skin (the bake's skin band times this), dark moss, the moss skirt.
const PALETTE := {"skin": "#857b69", "hair": "#2a2a1e", "cloth": "#4a5432", "faction": "#4a3a28"}
const BARK_TONE := Color(0.95, 0.92, 0.86)
## The glow of his sapwood and fungi (the shader's glow_energy) and of a broken plate's sapwood.
const GLOW := 1.1
const SAP_GLOW := 1.25

var model: Node3D = null
var skeleton: Skeleton3D = null
var body: MeshInstance3D = null
var player: AnimationPlayer = null
var pieces := {}          # node name -> MeshInstance3D
var body_material: ShaderMaterial = null
var bark_material: ShaderMaterial = null
var plate_materials := {}
var sap_materials := {}
var plate_cracks := {}
var plate_grows := {}
var sap_chars := {}
var clip := ""
var clip_time := 0.0


func _ready() -> void:
	if model == null:
		build()


static func entry() -> Dictionary:
	return BruteRig.creature_index().get(CREATURE, {})


static func facts() -> Dictionary:
	BruteRig.creature_index()
	return BruteRig._facts.get(CREATURE, {})


static func clip_keys() -> Dictionary:
	return entry().get("clip_keys", {})


## Loads the model and its clips and sets the materials; false when the asset is missing.
func build() -> bool:
	var e := entry()
	if e.is_empty() or not ResourceLoader.exists(str(e.get("scene", ""))):
		push_warning("RootwardenModel: the asset is missing (tools/giant/build_people.py --rootwarden)")
		return false
	model = (load(str(e.scene)) as PackedScene).instantiate() as Node3D
	model.name = MODEL_NAME
	add_child(model)
	var piece_names: Dictionary = e.get("pieces", {})
	var far := str(((e.get("variants", {}) as Dictionary).get(CREATURE, {}) as Dictionary).get("far", CREATURE + "_far"))
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := str(m.name)
		if n == CREATURE:
			body = m
		elif piece_names.has(n):
			pieces[n] = m
		elif n == far:
			m.visible = false
	if body == null:
		return false
	skeleton = body.get_node_or_null(body.skeleton) as Skeleton3D
	skeleton.name = "Skeleton3D"
	body_material = _person_material(e)
	bark_material = bark_material_of(e)
	body.material_override = body_material
	for n: String in pieces:
		var own := bark_material
		if n in PLATES:
			own = bark_material.duplicate() as ShaderMaterial
			plate_materials[n] = own
		elif n.begins_with("sap_"):
			own = bark_material.duplicate() as ShaderMaterial
			own.set_shader_parameter(&"glow_energy", SAP_GLOW)
			sap_materials[n] = own
			(pieces[n] as MeshInstance3D).visible = false
		(pieces[n] as MeshInstance3D).material_override = own
	if pieces.has("tree"):
		(pieces["tree"] as MeshInstance3D).visible = false
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	skeleton.get_parent().add_child(player)
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var lib := BruteRig.clip_library(CREATURE)
	if lib != null:
		player.add_animation_library(LIBRARY, lib)
	pose("idle", 0.0)
	return true


func _person_material(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PersonModel.PERSON_SHADER)
	for key: String in ["albedo", "normal", "orm"]:
		if ResourceLoader.exists(str(e.get(key, ""))):
			m.set_shader_parameter(StringName(key + "_tex"), load(str(e[key])))
	if ResourceLoader.exists(str(e.get("orm", ""))):
		m.set_shader_parameter(&"band_tex", load(str(e.orm)))
	for band: String in ["skin", "hair", "cloth", "faction"]:
		m.set_shader_parameter(StringName(band + "_color"), Color.html(str(PALETTE[band])))
	return m


## His bark's material: the stone shader on the bark texture, its cracks splits along the grain, the glow of the
## fungi and the sap seams (the Warden set's pieces and the grove's props share it).
static func bark_material_of(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	for key: String in ["albedo", "normal"]:
		var path := str(e.get("bark_" + key, ""))
		if ResourceLoader.exists(path):
			m.set_shader_parameter(StringName(key + "_tex"), load(path))
	m.set_shader_parameter(&"tone", BARK_TONE)
	m.set_shader_parameter(&"roughness_value", 0.9)
	m.set_shader_parameter(&"macro_strength", 0.3)
	m.set_shader_parameter(&"normal_depth", 1.4)
	m.set_shader_parameter(&"crack_grain", 1.0)
	m.set_shader_parameter(&"crack_cells", 2.0)
	m.set_shader_parameter(&"metal_wear", 0.2)
	m.set_shader_parameter(&"glow_energy", GLOW)
	return m


# --------------------------------------------------------------------------- poses

func clips() -> PackedStringArray:
	return player.get_animation_library(LIBRARY).get_animation_list() if player != null and player.has_animation_library(LIBRARY) else PackedStringArray()


func clip_length(name: String) -> float:
	return BruteRig.clip_length(CREATURE, name)


func has_clip(name: String) -> bool:
	return player != null and player.has_animation(StringName(String(LIBRARY) + "/" + name))


## Poses the skeleton at `t` seconds of `name` (now: the skeleton is updated before this returns).
func pose(name: String, t: float) -> void:
	if player == null or not player.has_animation_library(LIBRARY):
		return
	var full := StringName(String(LIBRARY) + "/" + name)
	if not player.has_animation(full):
		push_warning("RootwardenModel: no clip %s" % name)
		return
	clip = name
	clip_time = clampf(t, 0.0, clip_length(name))
	player.play(full)
	player.seek(clip_time, true)
	player.advance(0.0)


# --------------------------------------------------------------------------- the plates

func plate_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in PLATES:
		if pieces.has(n):
			out.append(n)
	return out


## Shows or hides plate `name` (its sapwood the other way round).
func set_plate_visible(name: String, on: bool) -> void:
	if pieces.has(name):
		(pieces[name] as MeshInstance3D).visible = on
	set_sap_visible(name, not on)


func plate_visible(name: String) -> bool:
	return pieces.has(name) and (pieces[name] as MeshInstance3D).visible


func set_sap_visible(plate: String, on: bool) -> void:
	var n := "sap_" + plate
	if pieces.has(n):
		(pieces[n] as MeshInstance3D).visible = on


func sap_visible(plate: String) -> bool:
	var n := "sap_" + plate
	return pieces.has(n) and (pieces[n] as MeshInstance3D).visible


## Plate `name` split along its grain: 0 whole, CRACKED (about half its bark gone), BADLY_CRACKED (little left).
func set_plate_crack(name: String, amount: float) -> void:
	var m: ShaderMaterial = plate_materials.get(name)
	if m == null:
		return
	plate_cracks[name] = amount
	m.set_shader_parameter(&"crack", clampf(amount, 0.0, 1.0))


func plate_crack(name: String) -> float:
	return float(plate_cracks.get(name, 0.0))


## Plate `name` regrowing: 1 whole, below it eaten away with fresh bark at the edge (0: gone).
func set_plate_grow(name: String, amount: float) -> void:
	var m: ShaderMaterial = plate_materials.get(name)
	if m == null:
		return
	plate_grows[name] = amount
	m.set_shader_parameter(&"grow", clampf(amount, 0.0, 1.0))


func plate_grow(name: String) -> float:
	return float(plate_grows.get(name, 1.0))


## The sapwood under plate `plate` seared by fire (0 raw, 1 charred black).
func set_sap_char(plate: String, amount: float) -> void:
	var m: ShaderMaterial = sap_materials.get("sap_" + plate)
	if m == null:
		return
	sap_chars[plate] = amount
	m.set_shader_parameter(&"charred", clampf(amount, 0.0, 1.0))


func sap_char(plate: String) -> float:
	return float(sap_chars.get(plate, 0.0))


static func crack_for(frac: float) -> float:
	if frac > CRACK_AT:
		return 0.0
	return CRACKED if frac > BADLY_AT else BADLY_CRACKED


func set_plates(on: bool) -> void:
	for n in plate_names():
		set_plate_visible(n, on)


func set_tree(on: bool) -> void:
	if pieces.has("tree"):
		(pieces["tree"] as MeshInstance3D).visible = on


func tree_visible() -> bool:
	return pieces.has("tree") and (pieces["tree"] as MeshInstance3D).visible


func piece(name: String) -> MeshInstance3D:
	return pieces.get(name)


static func piece_bone(name: String) -> String:
	return str(((entry().get("pieces", {}) as Dictionary).get(name, {}) as Dictionary).get("bone", "spine_02"))


func bone_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone) if skeleton != null else -1
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else global_position


func bone_motion(bone: String) -> Transform3D:
	var i := skeleton.find_bone(bone) if skeleton != null else -1
	if i < 0:
		return Transform3D.IDENTITY
	var now := skeleton.global_transform * skeleton.get_bone_global_pose(i)
	var rest := skeleton.global_transform * skeleton.get_bone_global_rest(i)
	return now * rest.affine_inverse()


func piece_transform(name: String) -> Transform3D:
	var mi := piece(name)
	if mi == null:
		return global_transform
	return bone_motion(piece_bone(name)) * mi.global_transform


func piece_centre(name: String) -> Vector3:
	var mi := piece(name)
	if mi == null or mi.mesh == null:
		return global_position + Vector3.UP * 12.0
	return piece_transform(name) * mi.mesh.get_aabb().get_center()


## A point the manifest gives in a hand's bone frame (the tree's head and foot, the roots' tip), in the world.
func hand_point(piece_name: String, key: String, bone: String) -> Vector3:
	var local: Array = ((entry().get("pieces", {}) as Dictionary).get(piece_name, {}) as Dictionary).get(key, [0, 0, 0])
	var i := skeleton.find_bone(bone) if skeleton != null else -1
	if i < 0:
		return global_position
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i) * Vector3(float(local[0]), float(local[1]),
		float(local[2])))


func tree_head() -> Vector3:
	return hand_point("tree", "head_local", "hand_r")


func roots_tip() -> Vector3:
	return hand_point("roots", "tip_local", "hand_l")
