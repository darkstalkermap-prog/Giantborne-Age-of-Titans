class_name OgreKingModel
extends Node3D
## The Ogre King as a signature titan (B2): his model as the asset pipeline made it (tools/giant/kit/ogre_king.py),
## posed by clip and time - OgreKingRig poses it under his actor, the stills and the cutscene pose it alone. 8.5 m to the
## top of his head (8.9 m to his crown's points) in his file; the model faces +Z.
##
##   OgreKingModel
##   └ Model                      assets/creatures/ogre_king.glb
##     └ ogre_king_rig            the armature
##       ├ Skeleton3D             23 bones (the people's): the clips (ogre_king_clips.glb)
##       │ ├ ogre_king            the body, the loincloth and belt, the tusks (person.gdshader on his atlas)
##       │ ├ trophy_<name>        the breakable trophies, each its own mesh (stone_plate.gdshader on the oak texture,
##       │ │                      its iron and bronze in the vertex colour): crown, bell, wheel_l, wheel_r, keg
##       │ ├ chain_belt           the chain round his hips and its five helmets
##       │ └ ram                  the battering ram, rigid on the right hand
##       └ AnimationPlayer        manual: pose(clip, time)
##
## Each trophy has its own material, so it shows its damage alone (set_trophy_crack: the wood split along its grain,
## the metal dented; cracked below CRACK_AT of its health, badly below BADLY_AT) and hides when it breaks
## (set_trophy_visible: OgreKingRig drops a copy of it to the ground and throws its splinters).

const CREATURE := "ogre_king"
const MODEL_NAME := "Model"
const LIBRARY := &"ogre_king"
const WOOD_SHADER := "res://assets/shaders/stone_plate.gdshader"
const TROPHIES := ["trophy_crown", "trophy_bell", "trophy_wheel_l", "trophy_wheel_r", "trophy_keg"]
const CRACK_AT := 0.6
const BADLY_AT := 0.3
const CRACKED := 0.5
const BADLY_CRACKED := 0.9
## His colours: a sallow, mottled grey-olive hide (older and paler than the ogres' green), dark brows and marks, the
## loincloth's hide.
const PALETTE := {"skin": "#6a6a4e", "hair": "#241c16", "cloth": "#5b4430", "faction": "#6e1a1f"}
const WOOD_TONE := Color(0.96, 0.92, 0.86)

var model: Node3D = null
var skeleton: Skeleton3D = null
var body: MeshInstance3D = null
var player: AnimationPlayer = null
var pieces := {}          # node name -> MeshInstance3D (the trophies, the chain belt, the ram)
var body_material: ShaderMaterial = null
var wood_material: ShaderMaterial = null
var trophy_materials := {}
var trophy_cracks := {}
var clip := ""
var clip_time := 0.0


func _ready() -> void:
	if model == null:
		build()


static func entry() -> Dictionary:
	return BruteRig.creature_index().get(CREATURE, {})


## The manifest's facts of his asset (the clips' keys, the pieces' bones).
static func facts() -> Dictionary:
	BruteRig.creature_index()
	return BruteRig._facts.get(CREATURE, {})


static func clip_keys() -> Dictionary:
	return entry().get("clip_keys", {})


## Loads the model and its clips and sets the materials; false when the asset is missing.
func build() -> bool:
	var e := entry()
	if e.is_empty() or not ResourceLoader.exists(str(e.get("scene", ""))):
		push_warning("OgreKingModel: the asset is missing (tools/giant/build_people.py --ogre_king)")
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
	wood_material = _wood_material(e)
	body.material_override = body_material
	for n: String in pieces:
		var own := wood_material
		if n in TROPHIES:
			own = wood_material.duplicate() as ShaderMaterial
			trophy_materials[n] = own
		(pieces[n] as MeshInstance3D).material_override = own
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


func _wood_material(e: Dictionary) -> ShaderMaterial:
	return wood_material_of(e)


## His trophies' material: the stone shader on the oak texture, its cracks splits along the grain (crack_grain), the
## metal's wear light (TrophyDisplay shares it).
static func wood_material_of(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(WOOD_SHADER)
	for key: String in ["albedo", "normal"]:
		var path := str(e.get("wood_" + key, ""))
		if ResourceLoader.exists(path):
			m.set_shader_parameter(StringName(key + "_tex"), load(path))
	m.set_shader_parameter(&"tone", WOOD_TONE)
	m.set_shader_parameter(&"roughness_value", 0.82)
	m.set_shader_parameter(&"macro_strength", 0.25)
	m.set_shader_parameter(&"crack_grain", 1.0)
	m.set_shader_parameter(&"crack_cells", 2.2)
	m.set_shader_parameter(&"metal_wear", 0.25)
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
		push_warning("OgreKingModel: no clip %s" % name)
		return
	clip = name
	clip_time = clampf(t, 0.0, clip_length(name))
	player.play(full)
	player.seek(clip_time, true)
	player.advance(0.0)


# --------------------------------------------------------------------------- the trophies

func trophy_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in TROPHIES:
		if pieces.has(n):
			out.append(n)
	return out


func set_trophy_visible(name: String, on: bool) -> void:
	if pieces.has(name):
		(pieces[name] as MeshInstance3D).visible = on


func trophy_visible(name: String) -> bool:
	return pieces.has(name) and (pieces[name] as MeshInstance3D).visible


## Shows trophy `name` damaged: 0 whole, CRACKED (about half its health gone), BADLY_CRACKED (little left).
func set_trophy_crack(name: String, amount: float) -> void:
	var m: ShaderMaterial = trophy_materials.get(name)
	if m == null:
		return
	trophy_cracks[name] = amount
	m.set_shader_parameter(&"crack", clampf(amount, 0.0, 1.0))


func trophy_crack(name: String) -> float:
	return float(trophy_cracks.get(name, 0.0))


## The crack shown with `frac` of a trophy's health left (CRACK_AT, BADLY_AT).
static func crack_for(frac: float) -> float:
	if frac > CRACK_AT:
		return 0.0
	return CRACKED if frac > BADLY_AT else BADLY_CRACKED


func set_trophies(on: bool) -> void:
	for n in trophy_names():
		set_trophy_visible(n, on)


func piece(name: String) -> MeshInstance3D:
	return pieces.get(name)


## The bone a piece rides on (the manifest's): its splinters fly from there, its fall starts from its pose there.
static func piece_bone(name: String) -> String:
	return str(((entry().get("pieces", {}) as Dictionary).get(name, {}) as Dictionary).get("bone", "spine_02"))


func bone_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone) if skeleton != null else -1
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else global_position


## The bone's rigid motion from its rest to its pose, in the world (world -> world).
func bone_motion(bone: String) -> Transform3D:
	var i := skeleton.find_bone(bone) if skeleton != null else -1
	if i < 0:
		return Transform3D.IDENTITY
	var now := skeleton.global_transform * skeleton.get_bone_global_pose(i)
	var rest := skeleton.global_transform * skeleton.get_bone_global_rest(i)
	return now * rest.affine_inverse()


## Where piece `name` is drawn now as a rigid body: its bone's motion of its rest placement (a static copy of its
## mesh with this transform lies where the skinned piece is).
func piece_transform(name: String) -> Transform3D:
	var mi := piece(name)
	if mi == null:
		return global_transform
	return bone_motion(piece_bone(name)) * mi.global_transform


## The centre of a piece as it is drawn now (its rest bounds carried by its bone).
func piece_centre(name: String) -> Vector3:
	var mi := piece(name)
	if mi == null or mi.mesh == null:
		return global_position + Vector3.UP * 5.0
	return piece_transform(name) * mi.mesh.get_aabb().get_center()


## The ram's head in the world: the manifest's point in the right hand's bone frame.
func ram_head() -> Vector3:
	var local: Array = ((entry().get("pieces", {}) as Dictionary).get("ram", {}) as Dictionary).get("head_local", [0, 0, 0])
	var i := skeleton.find_bone("hand_r") if skeleton != null else -1
	if i < 0:
		return global_position
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i) * Vector3(float(local[0]), float(local[1]), float(local[2])))
