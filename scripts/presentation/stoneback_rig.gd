class_name StonebackRig
extends Node3D
## Stoneback, the quarry titan (A1): his model as the asset pipeline made it (tools/giant/kit/stoneback.py), posed
## for stills. Presentation only and no actor yet: no AI, no fight, no encounter (a later package puts this model
## under an actor, as BruteRig does the ogre's). 16.8 m (55 ft) tall in his file; the model faces +Z.
##
##   StonebackRig
##   └ Model                      assets/creatures/stoneback.glb
##     └ stoneback_rig            the armature
##       ├ Skeleton3D             23 bones (the people's): the clips (stoneback_clips.glb)
##       │ ├ stoneback            the body and the hide kilt (person.gdshader on his atlas)
##       │ ├ plate_<name>         the stone plates, each its own mesh (stone_plate.gdshader on the stone texture):
##       │ │                      shoulder_l, shoulder_r, back, brow (the weak points'), forearm_l/_r, shin_l/_r
##       │ ├ shackles             the iron cuffs and their broken chains (his atlas's metal tile)
##       │ ├ club                 the uprooted trunk, rigid on the right hand (the bark texture)
##       │ └ boulder              the throw's rock, rigid on the left hand (hidden but in the throw)
##       └ AnimationPlayer        manual: pose(clip, time)
##
## The clips: idle, walk, run (loops), roar, and the attacks' wind-ups overhead, charge, throw (each from the stance
## to its peak, the clip's end: pose_windup()).

const CREATURE := "stoneback"
const MODEL_NAME := "Model"
const LIBRARY := &"stoneback"
const STONE_SHADER := "res://assets/shaders/stone_plate.gdshader"
## The plates whose breaking exposes a weak point (the manifest's weak_points), and the rest.
const WEAK_PLATES := ["plate_shoulder_l", "plate_shoulder_r", "plate_back", "plate_brow"]
const LIMB_PLATES := ["plate_forearm_l", "plate_forearm_r", "plate_shin_l", "plate_shin_r"]
const WINDUPS := ["overhead", "charge", "throw"]
## His colours: the skin band (a weathered umber hide, not the ogres' and trolls' greens), the brows' and marks'.
const PALETTE := {"skin": "#937868", "hair": "#2b231e", "cloth": "#5a4632", "faction": "#5c5246"}
## The stone's and the wood's tone over their detail textures.
const STONE_TONE := Color(1.0, 0.97, 0.92)
const BARK_TONE := Color(0.95, 0.92, 0.88)

var model: Node3D = null
var skeleton: Skeleton3D = null
var body: MeshInstance3D = null
var player: AnimationPlayer = null
var pieces := {}          # node name -> MeshInstance3D (the plates, the shackles, the club, the boulder)
var body_material: ShaderMaterial = null
var stone_material: ShaderMaterial = null
var bark_material: ShaderMaterial = null
var clip := ""
var clip_time := 0.0


func _ready() -> void:
	if model == null:
		build()


## The creatures' index entry of Stoneback ({} when the asset is missing).
static func entry() -> Dictionary:
	return BruteRig.creature_index().get(CREATURE, {})


## Loads the model and its clips and sets the materials; false when the asset is missing.
func build() -> bool:
	var e := entry()
	if e.is_empty() or not ResourceLoader.exists(str(e.get("scene", ""))):
		push_warning("StonebackRig: the asset is missing (tools/giant/build_people.py --stoneback)")
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
	stone_material = _detail_material(e, "stone", STONE_TONE)
	bark_material = _detail_material(e, "bark", BARK_TONE)
	body.material_override = body_material
	for n: String in pieces:
		var kind := str((piece_names[n] as Dictionary).get("material", "stone"))
		(pieces[n] as MeshInstance3D).material_override = body_material if kind == "body" else (
			bark_material if kind == "bark" else stone_material)
	set_boulder(false)
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


func _detail_material(e: Dictionary, what: String, tone: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(STONE_SHADER)
	for key: String in ["albedo", "normal"]:
		var path := str(e.get("%s_%s" % [what, key], ""))
		if ResourceLoader.exists(path):
			m.set_shader_parameter(StringName(key + "_tex"), load(path))
	m.set_shader_parameter(&"tone", tone)
	if what == "bark":
		m.set_shader_parameter(&"roughness_value", 0.85)
		m.set_shader_parameter(&"macro_strength", 0.3)
	return m


# --------------------------------------------------------------------------- poses

## The clip's names.
func clips() -> PackedStringArray:
	return player.get_animation_library(LIBRARY).get_animation_list() if player != null and player.has_animation_library(LIBRARY) else PackedStringArray()


func clip_length(name: String) -> float:
	return BruteRig.clip_length(CREATURE, name)


## Poses the skeleton at `t` seconds of `name` (now: the skeleton is updated before this returns). The throw shows
## the boulder.
func pose(name: String, t: float) -> void:
	if player == null or not player.has_animation_library(LIBRARY):
		return
	var full := StringName(String(LIBRARY) + "/" + name)
	if not player.has_animation(full):
		push_warning("StonebackRig: no clip %s" % name)
		return
	clip = name
	clip_time = clamp(t, 0.0, clip_length(name))
	player.play(full)
	player.seek(clip_time, true)
	player.advance(0.0)
	set_boulder(name == "throw")


## An attack's wind-up at its peak (the clip's last key).
func pose_windup(name: String) -> void:
	pose(name, clip_length(name))


# --------------------------------------------------------------------------- the plates

func plate_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in pieces:
		if n.begins_with("plate_"):
			out.append(n)
	return out


func set_plate_visible(name: String, on: bool) -> void:
	if pieces.has(name) and name.begins_with("plate_"):
		(pieces[name] as MeshInstance3D).visible = on


func plate_visible(name: String) -> bool:
	return pieces.has(name) and (pieces[name] as MeshInstance3D).visible


## Every plate shown (or hidden).
func set_plates(on: bool) -> void:
	for n in plate_names():
		set_plate_visible(n, on)


func set_boulder(on: bool) -> void:
	if pieces.has("boulder"):
		(pieces.boulder as MeshInstance3D).visible = on


func piece(name: String) -> MeshInstance3D:
	return pieces.get(name)


## A bone's posed position in the world (for framing).
func bone_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone) if skeleton != null else -1
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else global_position


## The club's head (the root ball's centre) in the world: the manifest's point in the right hand's bone frame.
func club_head() -> Vector3:
	var local: Array = ((entry().get("pieces", {}) as Dictionary).get("club", {}) as Dictionary).get("head_local", [0, 0, 0])
	var i := skeleton.find_bone("hand_r") if skeleton != null else -1
	if i < 0:
		return global_position
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i) * Vector3(float(local[0]), float(local[1]), float(local[2])))
