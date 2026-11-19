class_name GiantPreview
extends SubViewportContainer
## The creator's preview of the realistic giant (P44; plan M10 §2.10): a SubViewport with its own world
## (own_world_3d) holding the same giant_model.tscn and GiantLook the game draws, so the preview can never
## disagree with the game. Its own environment: a dark backdrop, ambient light, a key light with shadows, a
## cool rim light and a stone disc to stand on; MSAA 2x on desktop, off on the Web. It redraws only while
## visible (UPDATE_WHEN_VISIBLE); a portrait draws once (render_once, UPDATE_ONCE). It and its animation run
## with PROCESS_MODE_ALWAYS: the tree is paused while a shrine's screen is open.
##
## The giant idles with the model's idle clip when it has one (GiantModel.play_idle, P43's), else stands in
## GiantModel.pose_relaxed(). At a shrine it holds the equipped weapon, placed at GiantModel.hand_transform()
## and aimed along TipMatching.idle_grip(family).
##
## Framings (frame()): "full" (the whole giant, three-quarter front), "face", "hair" (three-quarter from
## behind, where styles differ), "back" (the whole giant from behind), and the design regions "arms",
## "chest", "back_design", "hand"; the category's framing is CreatorScreen's choice. set_view() is the view
## buttons' Full / Face / Back / Game view; "game" shows the giant at the stage's size from the game's
## default third-person camera (the stage profile's pivot height, shoulder offset and distance, pitch -18
## degrees, the settings' field of view), in the world's light (its sky, ambient, sun and fog), on the
## ground, with a soldier beside him for scale (game_camera_transform()).
##
## The user turns the giant (turn(): a mouse drag, the right stick, Q and E) and zooms (zoom(): the wheel,
## LT and RT, + and -). set_fade() fades the covering garments while a "Hidden by your clothing" row has the
## focus.
##
## Resolution (M10 gate, LA-3): the project stretches its 1280x720 canvas to the window (canvas_items), so a
## stretched container's SubViewport is the container's size in canvas units and the giant was drawn at about
## 720x550 in every window, 1.5x upscaled at 1920x1080 and 2x at 2560x1440. With `window_pixels` (the
## creator sets it) the preview fills its parent at the window's resolution instead: the container is
## pixel_scale() times its parent's size and scaled down by the same factor, so its SubViewport has one pixel
## per window pixel (up to MAX_PIXEL_SCALE; on the Web up to WEB_MAX_PIXEL_SCALE, measured by P49: pixel_scale()).
##
## P55 (plan M11 §2.7): the slots' framings (head, shoulders, waist, legs, shins, feet), a design region framed from
## the giant's left (`<framing>_left`: region_framing(region, side)), the stage-1 rear Game view (GAME_STAGE1) and
## the thumbnail mode (`thumbnail`: a fixed-size, still, unshown preview that ThumbnailCache draws once per option).
##
## WarmUp (an inner class) is the title's shader warm-up: a hidden 64x64 SubViewport that draws the model
## with every material category for two frames under this preview's lighting and two under a level's.

const MODEL := preload("res://scenes/player/giant_model.tscn")
const SOLDIER_SCENE := "res://scenes/enemies/soldier.tscn"
## The model is built at the stage-1 height (k = height / STAGE1_HEIGHT_M).
const STAGE1_HEIGHT_M := 3.6576
const BACKDROP := Color(0.07, 0.08, 0.10)
const PREVIEW_FOV := 30.0
## The game's third-person camera (CameraRig): its pitch at rest and the settings' field of view default.
const GAME_PITCH_DEG := -18.0
const GAME_FOV_DEFAULT := 75.0
## The world's light (tools/builders/world.gd): the sky, ambient and sun of the Old Kingdom.
const WORLD_SKY := Color(0.58, 0.66, 0.76)
const WORLD_AMBIENT := Color(0.62, 0.64, 0.7)
const WORLD_AMBIENT_ENERGY := 0.62
const WORLD_SUN_DEG := Vector3(-48, -35, 0)
const WORLD_FOG_M := Vector2(120.0, 700.0)
const GROUND_COLOR := Color(0.36, 0.41, 0.27)
## The studio lights, in the light rig's frame (the camera at the rig's -Z, looking along +Z; a light travels
## along its own -Z): the warm, shadow-casting key from the camera's side, above and to one side of it, so the
## side of the giant the camera sees is the lit one; the cool rim from behind him, on the other side. The rig
## turns with the camera's yaw (the giant turns on his disc under fixed lights), so every framing and every
## turn is lit the same way.
const KEY_LIGHT_DEG := Vector3(-38, 215, 0)
const RIM_LIGHT_DEG := Vector3(-18, 20, 0)
## How far the turn and the zoom go: degrees a second of the right stick at full tilt, the zoom factor's range.
const TURN_DEG_S := 120.0
const ZOOM_MIN := 0.55
const ZOOM_MAX := 1.6
## The most window pixels per canvas unit the preview draws (`window_pixels`): 2 covers 2560x1440; a larger
## window is upscaled from there.
const MAX_PIXEL_SCALE := 2.0
## Framings in the model's frame at stage 1 (+X his right, +Y up, -Z his front): what the camera looks at,
## its yaw (0 = in front of him, 90 = at his right, 180 = behind), its pitch and distance.
const FRAMINGS := {
	"full": {"target": Vector3(0.0, 1.85, 0.0), "yaw": 20.0, "pitch": 3.0, "dist": 8.4},
	"face": {"target": Vector3(0.0, 3.36, -0.2), "yaw": 14.0, "pitch": 2.0, "dist": 1.75},
	"hair": {"target": Vector3(0.0, 3.25, -0.02), "yaw": 140.0, "pitch": 12.0, "dist": 2.3},
	"back": {"target": Vector3(0.0, 1.9, 0.0), "yaw": 180.0, "pitch": 4.0, "dist": 8.4},
	"arms": {"target": Vector3(0.62, 2.55, -0.08), "yaw": 72.0, "pitch": 6.0, "dist": 2.7},
	"chest": {"target": Vector3(0.0, 2.7, -0.18), "yaw": 12.0, "pitch": 4.0, "dist": 2.4},
	"back_design": {"target": Vector3(0.0, 2.65, 0.12), "yaw": 180.0, "pitch": 6.0, "dist": 2.7},
	"hand": {"target": Vector3(0.72, 1.98, -0.12), "yaw": 55.0, "pitch": 14.0, "dist": 1.35},
	"hand_l": {"target": Vector3(-0.72, 1.98, -0.12), "yaw": -55.0, "pitch": 14.0, "dist": 1.35},
	# the character sheets' eye close-up (the index's eye_mid landmark)
	"eyes": {"target": Vector3(0.0, 3.447, -0.244), "yaw": 10.0, "pitch": 0.0, "dist": 0.36},
	# P55: the slots' framings (the creator II's option grids and their thumbnails; plan M11 §2.7)
	"head": {"target": Vector3(0.0, 3.42, -0.1), "yaw": 24.0, "pitch": 8.0, "dist": 1.9},
	"shoulders": {"target": Vector3(0.0, 2.95, -0.05), "yaw": 28.0, "pitch": 10.0, "dist": 2.6},
	"waist": {"target": Vector3(0.0, 1.85, -0.08), "yaw": 20.0, "pitch": 6.0, "dist": 2.6},
	"legs": {"target": Vector3(0.0, 1.05, -0.05), "yaw": 20.0, "pitch": 4.0, "dist": 4.4},
	"shins": {"target": Vector3(0.0, 0.62, -0.08), "yaw": 22.0, "pitch": 6.0, "dist": 2.5},
	"feet": {"target": Vector3(0.0, 0.32, -0.12), "yaw": 24.0, "pitch": 14.0, "dist": 1.9},
	# W32 (the creator on P54's wardrobe): a neck accessory's thumbnail - the torc at the neck's base from his right,
	# beside the beard that hides it from the front (the chest framing showed three identical beards)
	"neck": {"target": Vector3(0.0, 3.22, -0.04), "yaw": 64.0, "pitch": 2.0, "dist": 1.45},
	# the live preview while a slot's grid is open: the upper or the lower half, whole
	"upper": {"target": Vector3(0.0, 2.6, -0.05), "yaw": 22.0, "pitch": 5.0, "dist": 4.6},
	"lower": {"target": Vector3(0.0, 1.05, -0.05), "yaw": 22.0, "pitch": 5.0, "dist": 4.8},
	# a hair style's thumbnail: the head from behind, close
	"hair_close": {"target": Vector3(0.0, 3.22, 0.0), "yaw": 150.0, "pitch": 10.0, "dist": 1.75},
}
## P55 (M10's follow-up, plan M11 §2.7): a design on the giant's left is framed from his left - the framing's
## name with this suffix is the framing mirrored (its yaw and its target's x negated; "arms" follows the left hand).
const LEFT_SUFFIX := "_left"
## The framings a design region may be framed with from either side.
const MIRRORED := ["face", "chest", "arms", "back_design"]
## P55 (P51's follow-up): the eyes look toward the camera, as SkinnedRig._look_eyes turns them toward the game's -
## at most a quarter of the iris's radius (P51's `look`), an eye turned by an angle a taking a / (pi x EYE_IRIS_R),
## eased at EYE_RATE; straight ahead when the camera is behind him. Not in a still preview (the tiles, the sheets,
## the thumbnails).
const EYE_LOOK_MAX := 0.25
const EYE_IRIS_R := 0.168
const EYE_RATE := 10.0
## P55: the stage-1 rear Game view (the build sliders show it while they have the focus, plan M11 §2.7): the game's
## third-person camera behind the giant at stage 1's profile, whatever the profile Game view shows.
const GAME_STAGE1 := "game_stage1"
## The first-person framing (the option check and the sheets, not a view button): the game's eye at the
## stage's eye_height_ratio of the height and 0.18 m forward, looking down and to his right at the arms, with
## render layers 2 (torso) and 3 (head, hair, beard, eyes) culled as the game's first person does (decision 8).
const FIRST_PERSON := "first_person"
const FP_PITCH_DEG := -62.0
const FP_YAW_DEG := -22.0
const FP_FORWARD_M := 0.18
const FP_CULL := 0xFFFFF & ~(1 << 1) & ~(1 << 2)
## The view buttons, in X / V order.
const VIEWS := ["full", "face", "back", "game"]
const VIEW_NAMES := {"full": "Full", "face": "Face", "back": "Back", "game": "Game view"}

## The framing shown changed ("full", "face", ..., or "game").
signal framed(framing: String)

## Without a display the preview builds no materials (nothing draws; GiantLook.apply then sets visibility and
## stores the look, as on the headless player): tests that check the uniforms set this.
static var materials_headless := false

var viewport: SubViewport
var world_root: Node3D
var model: GiantModel
var camera: Camera3D
## The studio lights' rig: turned with the camera's yaw (_update_camera) so the key stays on the camera's side.
var light_rig: Node3D
var key_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var sun: DirectionalLight3D
var environment: Environment
var disc: MeshInstance3D
var ground: MeshInstance3D
## The framing in use and the view the buttons chose ("" = the category's framing).
var framing := "full"
var view := ""
## The user's turn (degrees added to the framing's yaw) and zoom factor.
var turn_deg := 0.0
var zoom_factor := 1.0
## The growth profile Game view shows (stage 1 until set_game_profile).
var game_profile: Dictionary = {}
## The look applied last and its cost (ms).
var last_apply_ms := 0.0
## A still giant (the option check's tiles, the character sheets): the relaxed pose, never the idle clip, so
## that every tile and page is drawn in one pose. Set before the preview enters the tree.
var still := false
## The world's light (its sun, sky, ambient, fog and ground) at every framing, not only in Game view and first
## person: the character sheets (plan §4.2). Read by frame().
var world_light := false
## Fill the parent Control at the window's resolution (see the class notes); set before or after the preview
## enters the tree. Off for the tiles of the option check and the sheets, which size their own viewports.
var window_pixels := false
## P55: a thumbnail preview (ThumbnailCache's): its viewport keeps the size it is given, draws only when
## render_thumbnail() asks, and never follows the container's visibility. Set before the preview enters the tree.
var thumbnail := false
var weapon: Node3D = null
var _weapon_dir := Vector3.FORWARD
var _soldier: Node3D = null
var _fade := 0.0
var _garments: Array = []   ## the garments of the look applied last (the skin's mask without a fade)
var _dragging := false
var _portrait := false
var _eye_mat: ShaderMaterial = null
var _eye_look := Vector2.ZERO
var _eye_sent := Vector2(INF, INF)


func _init() -> void:
	name = "GiantPreview"
	stretch = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.size = Vector2i(720, 544)
	add_child(viewport)
	world_root = Node3D.new()
	world_root.name = "Stage"
	viewport.add_child(world_root)
	_build_stage()
	model = MODEL.instantiate() as GiantModel
	model.name = "Model"
	world_root.add_child(model)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = PREVIEW_FOV
	camera.near = 0.05
	camera.far = 900.0
	world_root.add_child(camera)
	camera.current = true


func _ready() -> void:
	_apply_update_mode()
	_pose()
	if model != null and GiantLook.materials(model).is_empty() \
			and (materials_headless or DisplayServer.get_name() != "headless"):
		GiantLook.build_materials(model, model.index, "auto")
	if game_profile.is_empty():
		game_profile = stage_profile(1)
	frame(framing)
	fit_window_pixels()


## The model's index (the giant index of plan §2.5).
func index() -> Dictionary:
	return model.index if model != null else {}


## Puts `look` (Appearance.to_look) on the model; returns its cost in ms (recorded in last_apply_ms).
func apply_look(look: Dictionary) -> float:
	var t0 := Time.get_ticks_usec()
	GiantLook.apply(model, model.index, look)
	_garments = (look.get("garments", []) as Array).duplicate() if typeof(look.get("garments")) == TYPE_ARRAY else []
	if _fade > 0.0:
		GiantLook.set_garment_fade(model, model.index, _fade)
		_show_skin_under_fade()
	last_apply_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return last_apply_ms


## The idle when the model has one (P43's play_idle), else the relaxed pose; the weapon follows the hand.
func _pose() -> void:
	if model == null or not model.is_inside_tree():
		return
	if model.has_method("play_idle") and not still:
		model.call("play_idle")
	else:
		model.pose_relaxed()
	_place_weapon()


# --------------------------------------------------------------------------- the stage

func _build_stage() -> void:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	environment = Environment.new()
	we.environment = environment
	world_root.add_child(we)
	light_rig = Node3D.new()
	light_rig.name = "LightRig"
	world_root.add_child(light_rig)
	key_light = DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = KEY_LIGHT_DEG
	key_light.light_energy = 1.25
	key_light.light_color = Color(1.0, 0.95, 0.88)
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 30.0
	light_rig.add_child(key_light)
	rim_light = DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.rotation_degrees = RIM_LIGHT_DEG
	rim_light.light_energy = 0.7
	rim_light.light_color = Color(0.62, 0.74, 1.0)
	light_rig.add_child(rim_light)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = WORLD_SUN_DEG
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	world_root.add_child(sun)
	disc = MeshInstance3D.new()
	disc.name = "Disc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.7
	cyl.height = 0.12
	cyl.radial_segments = 40
	disc.mesh = cyl
	disc.position = Vector3(0, -0.06, 0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.33, 0.32, 0.30)
	stone.roughness = 0.95
	disc.material_override = stone
	world_root.add_child(disc)
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = GROUND_COLOR
	grass.roughness = 1.0
	ground.material_override = grass
	world_root.add_child(ground)
	_set_lighting(false)


## The preview's studio light (false) or the world's (true, Game view).
func _set_lighting(world: bool) -> void:
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = WORLD_SKY if world else BACKDROP
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = WORLD_AMBIENT if world else Color(0.46, 0.48, 0.54)
	environment.ambient_light_energy = WORLD_AMBIENT_ENERGY if world else 0.55
	environment.fog_enabled = world
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = WORLD_SKY
	environment.fog_depth_begin = WORLD_FOG_M.x
	environment.fog_depth_end = WORLD_FOG_M.y
	key_light.visible = not world
	rim_light.visible = not world
	sun.visible = world
	disc.visible = not world
	ground.visible = world
	if _soldier != null:
		_soldier.visible = world


## True while the stage shows the world's light (Game view).
func world_lighting() -> bool:
	return sun.visible


# --------------------------------------------------------------------------- framing

## Shows framing `name` (FRAMINGS, or "game"); the user's turn and zoom start over.
func frame(framing_name: String) -> void:
	if not framing_name in ["game", GAME_STAGE1, FIRST_PERSON] and not FRAMINGS.has(_base_framing(framing_name)):
		framing_name = "full"
	framing = framing_name
	turn_deg = 0.0
	zoom_factor = 1.0
	_set_lighting(world_light or _is_game(framing) or framing == FIRST_PERSON)
	_apply_stage_scale()
	_update_camera()
	framed.emit(framing)


## The view buttons (Full / Face / Back / Game view); "" goes back to the category's framing `fallback`.
func set_view(view_name: String, fallback := "full") -> void:
	view = view_name if view_name in VIEWS else ""
	frame(view if view != "" else fallback)


## The next view of VIEWS (pad X, key V) after the one shown.
func next_view() -> String:
	var i := VIEWS.find(view)
	return str(VIEWS[(i + 1) % VIEWS.size()])


## Turns the giant on his disc by `deg` (the camera orbits).
func turn(deg: float) -> void:
	turn_deg = wrapf(turn_deg + deg, -180.0, 180.0)
	_update_camera()


## Zooms by `steps` (positive: closer).
func zoom(steps: float) -> void:
	zoom_factor = clampf(zoom_factor * pow(0.9, steps), ZOOM_MIN, ZOOM_MAX)
	_update_camera()


## The growth profile Game view shows (the player's at a shrine; stage 1 at New Game).
func set_game_profile(profile: Dictionary) -> void:
	game_profile = profile
	if framing == "game":
		_apply_stage_scale()
		_update_camera()


## The growth profile of stage `n` ({} when the data has none).
static func stage_profile(n: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), n)


## k of the profile: its height over the model's stage-1 height.
static func stage_scale(profile: Dictionary) -> float:
	return maxf(0.1, float(profile.get("height_m", STAGE1_HEIGHT_M)) / STAGE1_HEIGHT_M)


## The game's default third-person camera for `profile` with the giant at the origin facing -Z (CameraRig at
## rest: yaw 0, pitch GAME_PITCH_DEG, the arm from the pivot over the right shoulder).
static func game_camera_transform(profile: Dictionary) -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(GAME_PITCH_DEG), 0.0, 0.0))
	var pivot := Vector3.UP * float(profile.get("camera_pivot_height_m", 3.3))
	var shoulder := float(profile.get("camera_shoulder_offset_m", 0.85))
	var desired := pivot + Vector3.RIGHT * shoulder + basis.z * float(profile.get("camera_distance_m", 6.5))
	return Transform3D(basis, desired)


## The field of view of the game's camera (the settings').
static func game_fov() -> float:
	var s: Variant = Settings.get_value("fov_deg") if Settings != null else GAME_FOV_DEFAULT
	return float(s) if s != null else GAME_FOV_DEFAULT


## True for the Game views (the profile's and the stage-1 rear one).
static func _is_game(framing_name: String) -> bool:
	return framing_name == "game" or framing_name == GAME_STAGE1


## The growth profile the framing shows: stage 1's for GAME_STAGE1, else game_profile.
func _framing_profile() -> Dictionary:
	if framing == GAME_STAGE1:
		var p := stage_profile(1)
		return p if not p.is_empty() else game_profile
	return game_profile


## A framing's FRAMINGS entry name ("chest_left" -> "chest").
static func _base_framing(framing_name: String) -> String:
	if framing_name.ends_with(LEFT_SUFFIX):
		var base := framing_name.trim_suffix(LEFT_SUFFIX)
		return base if base in MIRRORED else ""
	return framing_name


## A framing's FRAMINGS entry, mirrored for a "_left" framing.
static func framing_entry(framing_name: String) -> Dictionary:
	var base := _base_framing(framing_name)
	var f: Dictionary = (FRAMINGS.get(base, FRAMINGS.full) as Dictionary).duplicate()
	if framing_name != base:
		f["yaw"] = -float(f.yaw)
		var t: Vector3 = f.target
		f["target"] = Vector3(-t.x, t.y, t.z)
	return f


func _apply_stage_scale() -> void:
	var k := stage_scale(_framing_profile()) if _is_game(framing) or framing == FIRST_PERSON else 1.0
	model.scale = Vector3.ONE * k
	if _is_game(framing):
		_ensure_soldier()
		_soldier.position = Vector3(2.6 * k, 0.0, -2.2 * k)
		_soldier.visible = true
	elif _soldier != null:
		_soldier.visible = false


## The camera for the framing, the turn and the zoom.
func _update_camera() -> void:
	if camera == null:
		return
	camera.cull_mask = FP_CULL if framing == FIRST_PERSON else 0xFFFFF
	if framing == FIRST_PERSON:
		var eye := Vector3(0.0, float(game_profile.get("height_m", STAGE1_HEIGHT_M)) * float(game_profile.get("eye_height_ratio",
			0.92)), -FP_FORWARD_M)
		camera.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(FP_PITCH_DEG), deg_to_rad(FP_YAW_DEG + turn_deg), 0.0)),
			eye)
		camera.fov = game_fov()
		return
	if _is_game(framing):
		var profile := _framing_profile()
		var t := game_camera_transform(profile)
		var pivot := Vector3.UP * float(profile.get("camera_pivot_height_m", 3.3))
		var turned := Basis(Vector3.UP, deg_to_rad(turn_deg))
		camera.transform = Transform3D(turned * t.basis, pivot + turned * (t.origin - pivot) * zoom_factor)
		camera.fov = game_fov()
		return
	var f := framing_entry(framing)
	var target := framing_target(framing)
	var yaw := deg_to_rad(float(f.yaw) + turn_deg)
	var pitch := deg_to_rad(float(f.pitch))
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var from := target + dir * float(f.dist) * zoom_factor
	light_rig.rotation.y = -yaw   # the rig's -Z at the camera's side of the giant: the key lights what the camera sees
	camera.fov = PREVIEW_FOV
	camera.transform = Transform3D(Basis.looking_at(target - from, Vector3.UP), from)


## Where a framing looks (model frame, stage 1): its FRAMINGS target, the hand framing at the posed hand.
func framing_target(framing_name: String) -> Vector3:
	var f := framing_entry(framing_name)
	var arms_left := framing_name == "arms" + LEFT_SUFFIX
	if framing_name in ["hand", "hand_l", "arms"] or arms_left:
		if model != null and model.is_inside_tree() and model.skeleton() != null:
			var hand := model.to_local(model.hand_transform(framing_name != "hand_l" and not arms_left).origin)
			if framing_name in ["hand", "hand_l"]:
				return hand + Vector3(0, 0.06, 0)
			var lm := GiantModel.landmarks_of(model.index)
			var sh: Vector3 = lm.get("shoulder_l", Vector3(-0.41, 3.02, -0.03)) if arms_left else lm.get("shoulder_r",
				Vector3(0.41, 3.02, -0.03))
			return sh.lerp(hand, 0.5)
	return f.target


## The framing that shows a design region ("face", "chest", "back", "arms", "hand" or "hand_l": the left hand).
## P55: `side` is the design's side in the index ("left", "right" or "centre"): a design on the giant's left is
## framed from his left (M10's follow-up); the legs (P53's fifth region) are framed whole.
static func region_framing(region: String, side := "centre") -> String:
	var out := "full"
	match region:
		"face":
			out = "face"
		"chest":
			out = "chest"
		"back":
			out = "back_design"
		"arms":
			out = "arms"
		"legs":
			out = "legs"
		"hand", "hand_l":
			return region
	if side == "left" and out in MIRRORED:
		return out + LEFT_SUFFIX
	return out


# --------------------------------------------------------------------------- the soldier, the weapon, the fade

## A soldier for scale in Game view: the meshes of the game's soldier scene, without its scripts.
func _ensure_soldier() -> void:
	if _soldier != null:
		return
	_soldier = figure_of(SOLDIER_SCENE)
	_soldier.name = "Soldier"
	_soldier.rotation_degrees = Vector3(0, 200, 0)
	world_root.add_child(_soldier)


## The visible meshes of an actor scene (its Visual subtree, LOD proxy left out) as a plain Node3D, so a
## preview or a sheet can show a soldier or a villager without running their scripts.
static func figure_of(scene_path: String) -> Node3D:
	var root := Node3D.new()
	if not ResourceLoader.exists(scene_path):
		return root
	var inst := (load(scene_path) as PackedScene).instantiate()
	var visual := inst.get_node_or_null("Visual") as Node3D
	if visual != null:
		for mi in visual.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.name == "LodProxy" or not m.visible:
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = m.mesh
			copy.material_override = m.material_override
			copy.transform = _relative(m, inst)
			root.add_child(copy)
	inst.free()
	return root


static func _relative(n: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## The equipped weapon in the right hand (a shrine): WeaponVisuals of `rec` at `scale` (the weapon's
## effective scale at the giant's stage, as the rig holds it), aimed along TipMatching's resting grip.
func set_weapon(rec: Dictionary, weapon_scale := 1.0) -> void:
	clear_weapon()
	if rec.is_empty() or WeaponVisuals.shape_of(rec) == "none":
		return
	weapon = WeaponVisuals.build(rec)
	weapon.name = "Weapon"
	weapon.scale = Vector3.ONE * weapon_scale
	model.add_child(weapon)
	var family := str(rec.get("family", ""))
	var grip := TipMatching.from_index(model.index).idle_grip("tree" if WeaponVisuals.shape_of(rec) in ["tree", "pine"] else family)
	_weapon_dir = (grip.get("weapon_dir", Vector3.FORWARD) as Vector3).normalized()
	_place_weapon()


func clear_weapon() -> void:
	if weapon != null and is_instance_valid(weapon):
		weapon.queue_free()
	weapon = null


## The weapon's grip in the fist: the hand bone's pose, a little along the hand, pointing along the resting
## grip's direction (model frame).
func _place_weapon() -> void:
	if weapon == null or model == null or not model.is_inside_tree():
		return
	var hand := model.hand_transform(true)
	var local := model.global_transform.affine_inverse() * hand
	var grip := local.origin + local.basis.y.normalized() * 0.11
	var up := Vector3.UP if absf(_weapon_dir.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	weapon.transform = Transform3D(Basis.looking_at(_weapon_dir, up).scaled(weapon.scale), grip)


## The "Hidden by your clothing" fade (0-1) of the covering garments. While they fade, the skin under them is
## drawn whole (_show_skin_under_fade).
func set_fade(fade: float) -> void:
	_fade = clampf(fade, 0.0, 1.0)
	GiantLook.set_garment_fade(model, model.index, _fade)
	_show_skin_under_fade()


## Under a shown garment the skin's covered regions sink inside the body (giant_skin's hidden_regions), which
## leaves a jagged step along each region's border: unseen under cloth, but through faded cloth it showed as
## pale cut lines at the hips and dark notches at the shoulders (M10 gate, LA-5). While the garments fade no
## region sinks; without a fade the look's own mask is back.
func _show_skin_under_fade() -> void:
	var hidden := 0 if _fade > 0.0 else GiantLook.hidden_regions_mask(model.index, _garments)
	for mat: ShaderMaterial in GiantLook.materials(model):
		if mat.get_shader_parameter("hidden_regions") != null:
			GiantLook.set_param(mat, "hidden_regions", hidden)


func fade() -> float:
	return _fade


# --------------------------------------------------------------------------- drawing

## A portrait: the viewport draws once (UPDATE_ONCE) and then keeps that frame.
func render_once() -> void:
	_portrait = true
	_apply_update_mode()


## Back to drawing while visible (the creator open).
func render_live() -> void:
	_portrait = false
	_apply_update_mode()


## The SubViewportContainer sets its viewports to UPDATE_ALWAYS when it enters the tree or is shown (and
## UPDATE_DISABLED when hidden); the preview keeps its own mode instead: UPDATE_WHEN_VISIBLE while live,
## UPDATE_ONCE for a portrait, nothing while hidden.
func _apply_update_mode() -> void:
	if viewport == null:
		return
	if thumbnail:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if _portrait else SubViewport.UPDATE_DISABLED
		return
	if is_inside_tree() and not is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif _portrait:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_apply_update_mode()


func is_portrait() -> bool:
	return _portrait


## P55: a thumbnail preview draws its next frame once (ThumbnailCache reads it back after the frame is drawn).
func render_thumbnail() -> void:
	_portrait = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## P55: the thumbnail preview stops drawing (between thumbnails).
func stop_thumbnail() -> void:
	_portrait = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if window_pixels:
		fit_window_pixels()
	if weapon != null:
		_place_weapon()
	_look_eyes(delta)


## Where the eyes look for the camera now ((0, 0) when it is behind him or out of reach): x toward his right, y up,
## in the iris's radius (P51's `look`), from the eyes' landmark in the model's frame.
func eye_target() -> Vector2:
	if model == null or camera == null or not model.is_inside_tree():
		return Vector2.ZERO
	var eye: Vector3 = GiantModel.landmarks_of(model.index).get("eye_mid", Vector3(0.0, 3.447, -0.244))
	var d := model.global_transform.affine_inverse() * camera.global_position - eye
	if d.length_squared() < 1e-8:
		return Vector2.ZERO
	d = d.normalized()
	var ahead := -d.z
	if ahead <= 0.05:
		return Vector2.ZERO
	var per := 1.0 / (PI * EYE_IRIS_R)
	return Vector2(clampf(atan2(d.x, ahead) * per, -EYE_LOOK_MAX, EYE_LOOK_MAX),
		clampf(atan2(d.y, Vector2(d.x, ahead).length()) * per, -EYE_LOOK_MAX, EYE_LOOK_MAX))


func _look_eyes(delta: float) -> void:
	if still or thumbnail or model == null:
		return
	if _eye_mat == null:
		for id in GiantLook.meshes_of(model.index, "eyes"):
			var eyes := GiantLook.mesh_node(model, model.index, id)
			if eyes != null and eyes.material_override is ShaderMaterial:
				_eye_mat = eyes.material_override as ShaderMaterial
		if _eye_mat == null:
			return
	_eye_look = _eye_look.lerp(eye_target(), 1.0 - exp(-EYE_RATE * delta))
	if _eye_look.distance_squared_to(_eye_sent) > 1e-8:
		_eye_sent = _eye_look
		GiantLook.set_param(_eye_mat, "look", _eye_look)


# --------------------------------------------------------------------------- resolution

## P49 (plan M11 §3.2 item 8; the M10 gate's LA-3 for the Web): the most viewport pixels per canvas unit on
## the Web: the largest scale whose first creator frame stays within the stall rule (3 times the median frame).
## Measured in headless Chromium on software WebGL at 1920x1080 (creator_check.mjs --args=--preview-scale=N,
## New Game): 1 - 2.12x, 1.5 - 1.82x, 2 - 1.44x, every one within it, so the Web follows the desktop up to 2;
## the steady creator frame there cost 254, 340 and 455 ms (docs/systems/P49.md).
const WEB_MAX_PIXEL_SCALE := 2.0
## --preview-scale=N on the command line (after "--") makes pixel_scale() return N (1 to MAX_PIXEL_SCALE)
## whatever the window: the Web measurement of P49 (tools/web/creator_check.mjs --args=--preview-scale=1.5).
const SCALE_OPTION := "--preview-scale="
static var _forced_scale := -1.0   # -1: the command line was not read yet; 0: no option


## The forced scale of --preview-scale=N (0 when the option is not given).
static func forced_pixel_scale() -> float:
	if _forced_scale < 0.0:
		_forced_scale = 0.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with(SCALE_OPTION) and a.substr(SCALE_OPTION.length()).is_valid_float():
				_forced_scale = clampf(a.substr(SCALE_OPTION.length()).to_float(), 1.0, MAX_PIXEL_SCALE)
	return _forced_scale


## Window pixels per canvas unit for the preview's SubViewport: the scale the window stretches the canvas by,
## from 1 (never under the canvas's own size) to MAX_PIXEL_SCALE, on the Web to WEB_MAX_PIXEL_SCALE.
func pixel_scale() -> float:
	if not is_inside_tree():
		return 1.0
	if forced_pixel_scale() > 0.0:
		return forced_pixel_scale()
	var s := get_viewport().get_final_transform().get_scale()
	return clampf(minf(absf(s.x), absf(s.y)), 1.0, WEB_MAX_PIXEL_SCALE if OS.has_feature("web") else MAX_PIXEL_SCALE)


## With `window_pixels`: fills the parent Control with a container pixel_scale() times its size, scaled down by
## the same factor, so the stretched SubViewport is drawn 1:1 in window pixels. Called every frame (a window
## can change its scale without changing the canvas's size); does nothing when nothing changed.
func fit_window_pixels() -> void:
	if not window_pixels or not is_inside_tree():
		return
	var parent := get_parent() as Control
	if parent == null:
		return
	var k := pixel_scale()
	var want := (parent.size * k).floor().max(Vector2.ONE)
	var down := Vector2.ONE / k
	if size.is_equal_approx(want) and scale.is_equal_approx(down) and position.is_zero_approx():
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = down
	size = want


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(-1)
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		turn(-mm.relative.x * scale.x * 0.4)   # in canvas units, whatever the container's own scale (window_pixels)
		accept_event()


# --------------------------------------------------------------------------- the title's warm-up

## The title's shader warm-up (plan M10 §2.10): a hidden 64x64 SubViewport with its own world that draws the
## model in the default look (skin, eyes, hair, beard and cloth: every material category) for FRAMES_EACH
## frames under the preview's lighting (a shadowed key light and the rim, no fog), then FRAMES_EACH under a
## level's (a shadowed sun and fog). `finished` fires after those frames; the title enables its buttons then
## (or after its own time limit). It stops drawing when done and is freed with the title or when a level loads.
class WarmUp extends SubViewport:
	signal finished
	const FRAMES_EACH := 2
	const SIZE := 64

	var model: GiantModel
	var env: Environment
	var key: DirectionalLight3D
	var rim: DirectionalLight3D
	var sun: DirectionalLight3D
	var frames := 0
	var done := false
	var _root: Node3D

	func _init() -> void:
		name = "GiantWarmUp"
		size = Vector2i(SIZE, SIZE)
		own_world_3d = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_root = Node3D.new()
		add_child(_root)
		var we := WorldEnvironment.new()
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = GiantPreview.BACKDROP
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.46, 0.48, 0.54)
		we.environment = env
		_root.add_child(we)
		key = DirectionalLight3D.new()
		key.rotation_degrees = GiantPreview.KEY_LIGHT_DEG
		key.shadow_enabled = true
		_root.add_child(key)
		rim = DirectionalLight3D.new()
		rim.rotation_degrees = GiantPreview.RIM_LIGHT_DEG
		_root.add_child(rim)
		sun = DirectionalLight3D.new()
		sun.rotation_degrees = GiantPreview.WORLD_SUN_DEG
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.visible = false
		_root.add_child(sun)
		model = GiantPreview.MODEL.instantiate() as GiantModel
		_root.add_child(model)
		var cam := Camera3D.new()
		cam.fov = 40.0
		_root.add_child(cam)
		cam.position = Vector3(0, 1.9, -6.5)
		cam.look_at_from_position(cam.position, Vector3(0, 1.9, 0), Vector3.UP)
		cam.current = true

	func _ready() -> void:
		GiantLook.build_materials(model, model.index, "auto")
		GiantLook.apply(model, model.index, GiantLook.DEFAULT_LOOK)
		GiantLook.warm_shells(model, model.index)   # P51: the shell styles' shader too (the crop, the short beard)
		RenderingServer.frame_post_draw.connect(_on_drawn)

	func _exit_tree() -> void:
		if RenderingServer.frame_post_draw.is_connected(_on_drawn):
			RenderingServer.frame_post_draw.disconnect(_on_drawn)

	## Without a display nothing is drawn: the frames are counted here instead (tests).
	func _process(_delta: float) -> void:
		if DisplayServer.get_name() == "headless":
			_on_drawn()

	## The level's lighting: the sun and fog instead of the studio lights.
	func _level_light() -> void:
		key.visible = false
		rim.visible = false
		sun.visible = true
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.background_color = GiantPreview.WORLD_SKY

	func _on_drawn() -> void:
		if done:
			return
		frames += 1
		if frames == FRAMES_EACH:
			_level_light()
		elif frames >= FRAMES_EACH * 2:
			done = true
			render_target_update_mode = SubViewport.UPDATE_DISABLED
			finished.emit()
