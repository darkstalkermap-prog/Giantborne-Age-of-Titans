class_name FrostboundModel
extends Node3D
## The Frostbound Titan (D1): his model as the asset pipeline made it (tools/giant/kit/frostbound.py), posed by clip and
## time - FrostboundRig poses it under his actor, the stills and the capture tours pose it alone. 28.0 m to the top of
## his head in his file; the model faces +Z.
##
##   FrostboundModel
##   └ Model                      assets/creatures/frostbound.glb
##     └ frostbound_rig           the armature
##       ├ Skeleton3D             23 bones (the people's): the clips (frostbound_clips.glb)
##       │ ├ frostbound           his body, frozen: the cold grey-blue skin rimed white, the frozen hide kilt
##       │ │                      (person.gdshader on his atlas)
##       │ ├ crown, pauldron_l, pauldron_r, serac, heart, gauntlet, greave_l, greave_r
##       │ │                      the breakable ice, each its own material (its fractures): the cairn-crown, the
##       │ │                      shoulders' ice, the serac crest on his back, the heart-ice, the ice fist, the greaves
##       │ └ beard, rime          the icicles of his jaw, his arms and his belt (gear)
##       └ AnimationPlayer        manual: pose(clip, time)
##
## Each plate shows its state alone: fractured as its ice wears (set_plate_crack), gone (set_plate_visible: the rig
## throws its shards). The heart's core pulses (set_heart_pulse).

const CREATURE := "frostbound"
const MODEL_NAME := "Model"
const LIBRARY := &"frostbound"
const SHADER := "res://assets/shaders/ice_plate.gdshader"
const PLATES := ["crown", "pauldron_l", "pauldron_r", "serac", "heart", "gauntlet", "greave_l", "greave_r"]
const GEAR := ["beard", "rime"]
const CRACK_AT := 0.6
const BADLY_AT := 0.3
const CRACKED := 0.5
const BADLY_CRACKED := 0.9
## His colours: a cold grey-blue skin (the bake's skin band times this), the frost-white of his scalp, the frozen hide.
const PALETTE := {"skin": "#a3b2bf", "hair": "#d8e0e6", "cloth": "#5a5650", "faction": "#4a5058"}
const ICE_TONE := Color(1.0, 1.0, 1.0)

var model: Node3D = null
var skeleton: Skeleton3D = null
var body: MeshInstance3D = null
var player: AnimationPlayer = null
var pieces := {}          # node name -> MeshInstance3D
var body_material: ShaderMaterial = null
var ice_material: ShaderMaterial = null
var plate_materials := {}
var plate_cracks := {}
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
		push_warning("FrostboundModel: the asset is missing (tools/giant/build_people.py --frostbound)")
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
	ice_material = ice_material_of(e)
	body.material_override = body_material
	for n: String in pieces:
		var own := ice_material
		if n in PLATES:
			own = ice_material.duplicate() as ShaderMaterial
			plate_materials[n] = own
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


## His ice's material: the ice shader on Stoneback's stone maps (the Frostbound set's pieces share it).
static func ice_material_of(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	for key: String in ["albedo", "normal"]:
		var path := str(e.get("ice_" + key, ""))
		if ResourceLoader.exists(path):
			m.set_shader_parameter(StringName(key + "_tex"), load(path))
	m.set_shader_parameter(&"tone", ICE_TONE)
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
		push_warning("FrostboundModel: no clip %s" % name)
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


func set_plate_visible(name: String, on: bool) -> void:
	if pieces.has(name):
		(pieces[name] as MeshInstance3D).visible = on


func plate_visible(name: String) -> bool:
	return pieces.has(name) and (pieces[name] as MeshInstance3D).visible


## Plate `name` fractured: 0 whole, CRACKED (about half its ice gone), BADLY_CRACKED (little left).
func set_plate_crack(name: String, amount: float) -> void:
	var m: ShaderMaterial = plate_materials.get(name)
	if m == null:
		return
	plate_cracks[name] = amount
	m.set_shader_parameter(&"crack", clampf(amount, 0.0, 1.0))


func plate_crack(name: String) -> float:
	return float(plate_cracks.get(name, 0.0))


static func crack_for(frac: float) -> float:
	if frac > CRACK_AT:
		return 0.0
	return CRACKED if frac > BADLY_AT else BADLY_CRACKED


func set_plates(on: bool) -> void:
	for n in plate_names():
		set_plate_visible(n, on)


## The heart's core's light (0..1: his cold welling up as he draws breath or gathers his nova).
func set_heart_pulse(amount: float) -> void:
	var m: ShaderMaterial = plate_materials.get("heart")
	if m != null:
		m.set_shader_parameter(&"pulse", clampf(amount, 0.0, 1.0))


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


## A piece's mesh posed now (its bone's rigid motion over its rest: the rigid fist exactly, a plate coarsely).
func piece_transform(name: String) -> Transform3D:
	var mi := piece(name)
	if mi == null:
		return global_transform
	return bone_motion(piece_bone(name)) * mi.global_transform


func piece_centre(name: String) -> Vector3:
	var mi := piece(name)
	if mi == null or mi.mesh == null:
		return global_position + Vector3.UP * 14.0
	return piece_transform(name) * mi.mesh.get_aabb().get_center()


## The ice fist's mass's centre in the world (the manifest's mass_local in the right hand's frame).
func fist_centre() -> Vector3:
	var local: Array = ((entry().get("pieces", {}) as Dictionary).get("gauntlet", {}) as Dictionary).get("mass_local",
		[0, 0, 0])
	var i := skeleton.find_bone("hand_r") if skeleton != null else -1
	if i < 0:
		return global_position
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i) * Vector3(float(local[0]), float(local[1]),
		float(local[2])))


## His mouth (the breath's source): the head bone's position pushed forward and down a little.
func mouth() -> Vector3:
	var i := skeleton.find_bone("head") if skeleton != null else -1
	if i < 0:
		return global_position + Vector3.UP * 24.0
	var t := skeleton.global_transform * skeleton.get_bone_global_pose(i)
	return t * Vector3(0.0, 0.6, 1.4)
