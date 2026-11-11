class_name SceneryFade
extends RefCounted
## Trees that fade out of the giant's way (M8 screenshot pass, V1). The trees of the world's chunks
## and of the Valley's districts are drawn with assets/shaders/scenery_fade.gdshader, which dithers
## out (a 4 x 4 ordered dither, discard) the fragments that would hide the giant and his fight:
##   * near the camera: within the near radius (third person NEAR_ARM x the arm, first person
##     FP_NEAR_RADII x the giant's height) a tree fades out whole - the camera inside a pine's crown,
##     a crown at the screen's edge;
##   * the cone from the camera to the giant's middle (FOCUS_HEIGHT of his height), CONE_APEX_M wide
##     at the camera and FOCUS_RADII x his height at him - every sight line to his body lies inside -
##     going on past him as a cylinder for FOCUS_REACH_RADII x its radius, where what he fights
##     stands: CONE_FADE of the pixels go (a ghost of the tree stays), with a soft edge;
##   * the cone from the camera to the locked target's lock point (CameraRig.lock_focus_point),
##     TARGET_RADII x the target's height (at least TARGET_MIN_M; a formation's frontage) at it.
## The camera rig sets the three global shader parameters (declared in project.godot,
## shader_globals) every frame through set_view() and clears them when it leaves (clear()); w = 0
## switches a part off. fade_at() is the shader's rule on the CPU (tests: TreeSight); keep the
## shader's constants equal to these. test_scenery_fade holds the two to one rule: it runs the shader's
## own text on the CPU (tests/support/shader_rule.gd) against fade_at() and discarded_share() - its
## constants, its global uniforms, the fade round random views and its dither.
##
## Why a fade and not the camera's obstruction probe: in the Greywood the pines stand 9 m apart and
## their crowns are 5-9 m wide from 0.5 m up, so a stage-4 camera 12-20 m behind the giant always has
## one between it and him, and the giant himself often stands inside one's lowest crown; pulling the
## arm in front of crowns would hold it at a few metres among them, and the trunks (the only tree
## colliders, on the world layer, which the probe already sweeps) are not what hides him. The fade
## keeps the camera where the player put it, costs no draw call (the same MultiMeshes, another
## material), works in gl_compatibility and WebGL2, and leaves the trees' shadows whole (a pass whose
## eye is not this camera - a shadow pass - fades nothing).

const PARAM_CAMERA := &"scenery_fade_camera"
const PARAM_FOCUS := &"scenery_fade_focus"
const PARAM_TARGET := &"scenery_fade_target"

## The share of a fragment's pixels the dither removes inside a cone (the rest is the tree's ghost).
const CONE_FADE := 0.8
## A cone's radius at the camera (m); it widens to its focus radius at the focus.
const CONE_APEX_M := 0.5
## A cone's soft edge: from its radius r out to r + r x CONE_EDGE + EDGE_M the fade falls to 0.
const CONE_EDGE := 0.35
const EDGE_M := 0.5
## Past its focus a cone goes on as a cylinder of the focus radius for this many radii, fading out
## over the second half: the giant's (where what he fights stands) and a locked target's.
const FOCUS_REACH_RADII := 1.4
const TARGET_REACH_RADII := 0.5
## The near sphere fades whole within NEAR_CORE of its radius, softly out to the radius.
const NEAR_CORE := 0.75
## A pass whose eye is farther than this from the camera parameter (a shadow pass) fades nothing.
const SAME_CAMERA_M := 0.5

## Third person: the near radius is NEAR_ARM x the arm (at least NEAR_MIN_M).
const NEAR_ARM := 0.45
const NEAR_MIN_M := 1.0
## First person: the near radius is FP_NEAR_RADII x the giant's height (his eye is in his head).
const FP_NEAR_RADII := 0.3
## The giant's focus: FOCUS_HEIGHT of his height above his feet; the cone's radius there FOCUS_RADII x
## his height (his head and feet lie at 0.45-0.5 x his height from it, inside the cone's core).
const FOCUS_HEIGHT := 0.5
const FOCUS_RADII := 0.7
## A locked target's cone radius: TARGET_RADII x its height, at least TARGET_MIN_M.
const TARGET_RADII := 0.7
const TARGET_MIN_M := 1.5

## What the camera last set (xyz, w as the shader's parameters); all zero when nothing fades.
static var camera := Vector4.ZERO
static var focus := Vector4.ZERO
static var target := Vector4.ZERO


## Sets the three parameters: the camera (its position and near radius), the giant's focus and the
## locked target's (w = 0: none).
static func set_view(p_camera: Vector4, p_focus: Vector4, p_target: Vector4) -> void:
	camera = p_camera
	focus = p_focus
	target = p_target
	RenderingServer.global_shader_parameter_set(PARAM_CAMERA, camera)
	RenderingServer.global_shader_parameter_set(PARAM_FOCUS, focus)
	RenderingServer.global_shader_parameter_set(PARAM_TARGET, target)


## Nothing fades (no camera rig: the loading screen, the title).
static func clear() -> void:
	set_view(Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)


## The fade at world point `p` with the parameters set now, for the camera's own pass (0 = drawn whole,
## 1 = gone).
static func fade_at_now(p: Vector3) -> float:
	return fade_at(p, Vector3(camera.x, camera.y, camera.z), camera, focus, target)


## The shader's rule: the fade of world point `p` seen by a pass whose eye is `eye`, with the
## parameters `cam`, `foc` and `tgt` (0 = drawn whole, 1 = gone).
static func fade_at(p: Vector3, eye: Vector3, cam: Vector4, foc: Vector4, tgt: Vector4) -> float:
	var c := Vector3(cam.x, cam.y, cam.z)
	if cam.w <= 0.0 or eye.distance_to(c) > SAME_CAMERA_M:
		return 0.0
	var f := 1.0 - smoothstep(cam.w * NEAR_CORE, cam.w, p.distance_to(c))
	f = maxf(f, cone_fade(p, c, foc, FOCUS_REACH_RADII))
	f = maxf(f, cone_fade(p, c, tgt, TARGET_REACH_RADII))
	return f


## The fade of `p` in the cone from `cam` to `foc` (xyz; w: its radius there), going on `reach_radii`
## x the radius past the focus.
static func cone_fade(p: Vector3, cam: Vector3, foc: Vector4, reach_radii: float) -> float:
	if foc.w <= 0.0:
		return 0.0
	var axis := Vector3(foc.x, foc.y, foc.z) - cam
	var length := axis.length()
	if length < 0.01:
		return 0.0
	axis /= length
	var rel := p - cam
	var s := rel.dot(axis)
	if s <= 0.0:
		return 0.0
	var d := (rel - axis * s).length()
	var r := CONE_APEX_M + foc.w * minf(s / length, 1.0)
	var across := 1.0 - smoothstep(r, r + r * CONE_EDGE + EDGE_M, d)
	var reach := foc.w * reach_radii
	var along := 1.0 - smoothstep(length + reach * 0.5, length + reach, s)
	return CONE_FADE * across * along


## The share of a surface's pixels a fade of `f` discards (the shader's 4 x 4 dither: a pixel goes when
## f >= its threshold, (k + 0.5) / 16 for k = 0..15).
static func discarded_share(f: float) -> float:
	if f <= 0.0:
		return 0.0
	var n := 0
	for k in 16:
		if f >= (float(k) + 0.5) / 16.0:
			n += 1
	return n / 16.0
